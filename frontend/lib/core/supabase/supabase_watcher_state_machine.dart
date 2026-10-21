import 'dart:async';

/// Event type for incremental PostgreSQL Realtime mutations.
enum WatcherEventType {
  upsert,
  delete,
  resync,
}

/// Generic event delivered from a Supabase Realtime channel or change signal.
class WatcherEvent<T> {
  const WatcherEvent.upsert(this.item, {this.id})
      : type = WatcherEventType.upsert;

  const WatcherEvent.delete(this.id)
      : type = WatcherEventType.delete,
        item = null;

  const WatcherEvent.resync()
      : type = WatcherEventType.resync,
        id = null,
        item = null;

  final WatcherEventType type;
  final String? id;
  final T? item;
}

/// A decoupled, testable state-machine for real-time table streams.
///
/// Features:
/// 1. Injected [fetcher] and [eventStream] for full test isolation.
/// 2. Error surfacing: errors from [fetcher] are sent to the stream controller.
/// 3. Resync replaces cache: a resync wipes stale state and adopts the authoritative snapshot.
/// 4. Delete removes row: incremental deletes strip the entry and emit the revised list.
/// 5. Reconnect: handles reconnect / auth-refresh signals by triggering a fresh resync.
/// 6. Late listeners: new subscribers immediately receive the currently cached list.
class SupabaseWatcherStateMachine<T> {
  SupabaseWatcherStateMachine({
    required this.fetcher,
    required this.getId,
    this.sort,
    this.eventStream,
    this.onSubscribe,
  });

  final Future<List<T>> Function() fetcher;
  final String Function(T item) getId;
  final void Function(List<T> items)? sort;
  final Stream<WatcherEvent<T>>? eventStream;
  final void Function()? onSubscribe;

  final Map<String, T> _cache = {};
  StreamController<List<T>>? _controller;
  StreamSubscription<WatcherEvent<T>>? _eventSub;
  bool _isDisposed = false;

  /// Returns a defensive copy of the current cached items.
  List<T> get cachedList {
    final list = _cache.values.toList();
    if (sort != null) {
      sort!(list);
    }
    return list;
  }

  /// Authoritatively resyncs the cache from the primary database [fetcher].
  Future<void> resync() async {
    if (_isDisposed) return;
    try {
      final items = await fetcher();
      if (_isDisposed) return;
      _cache.clear();
      for (final item in items) {
        _cache[getId(item)] = item;
      }
      if (_controller != null && !_controller!.isClosed) {
        _controller!.add(cachedList);
      }
    } catch (e, st) {
      if (_controller != null && !_controller!.isClosed) {
        _controller!.addError(e, st);
      }
    }
  }

  /// Processes an incremental mutation event (upsert, delete, or resync).
  void handleEvent(WatcherEvent<T> event) {
    if (_isDisposed) return;
    switch (event.type) {
      case WatcherEventType.upsert:
        if (event.item != null) {
          final id = event.id ?? getId(event.item!);
          _cache[id] = event.item!;
          if (_controller != null && !_controller!.isClosed) {
            _controller!.add(cachedList);
          }
        }
        break;
      case WatcherEventType.delete:
        if (event.id != null) {
          final removed = _cache.remove(event.id);
          if (removed != null && _controller != null && !_controller!.isClosed) {
            _controller!.add(cachedList);
          }
        }
        break;
      case WatcherEventType.resync:
        resync();
        break;
    }
  }

  /// Returns the broadcast stream for subscribers.
  Stream<List<T>> stream() {
    _controller ??= StreamController<List<T>>.broadcast(
      onListen: () {
        if (_cache.isNotEmpty && !_controller!.isClosed) {
          _controller!.add(cachedList);
        }
        _eventSub ??= eventStream?.listen(
          handleEvent,
          onError: (e, st) {
            if (_controller != null && !_controller!.isClosed) {
              _controller!.addError(e, st);
            }
          },
        );
        onSubscribe?.call();
        resync();
      },
      onCancel: () {
        if (_controller != null && !_controller!.hasListener) {
          _eventSub?.cancel();
          _eventSub = null;
        }
      },
    );

    return _controller!.stream;
  }

  /// Cleans up subscriptions and controllers.
  void dispose() {
    _isDisposed = true;
    _eventSub?.cancel();
    _eventSub = null;
    _controller?.close();
  }
}
