import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../firestore_read_helper.dart';

/// Binds Firestore data to UI with proper dispose cleanup.
///
/// Set [realtime] to false for one-time cache-first reads (lower billing).
/// Put your collection path in [query], e.g.:
/// `FirebaseFirestore.instance.collection(FirestorePaths.prescriptions).where(...).limit(20)`
class FirestoreSnapshotBuilder extends StatefulWidget {
  const FirestoreSnapshotBuilder({
    super.key,
    required this.query,
    required this.builder,
    this.realtime = false,
    this.preferCache = true,
    this.loading,
    this.error,
  });

  final Query<Map<String, dynamic>> query;
  final bool realtime;
  final bool preferCache;
  final Widget Function(
          BuildContext context, QuerySnapshot<Map<String, dynamic>> snapshot)
      builder;
  final Widget Function(BuildContext context)? loading;
  final Widget Function(BuildContext context, Object error)? error;

  @override
  State<FirestoreSnapshotBuilder> createState() =>
      _FirestoreSnapshotBuilderState();
}

class _FirestoreSnapshotBuilderState extends State<FirestoreSnapshotBuilder> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  QuerySnapshot<Map<String, dynamic>>? _snapshot;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.realtime) {
      _attachListener();
    } else {
      unawaited(_fetchOnce());
    }
  }

  void _attachListener() {
    _subscription = widget.query.snapshots().listen(
      (snapshot) {
        if (!mounted) return;
        setState(() {
          _snapshot = snapshot;
          _loading = false;
          _error = null;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _error = error;
          _loading = false;
        });
      },
    );
  }

  Future<void> _fetchOnce() async {
    try {
      final snapshot = await FirestoreReadHelper.getQuery(
        query: widget.query,
        preferCache: widget.preferCache,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return widget.error?.call(context, _error!) ??
          Center(child: Text('Firestore error: $_error'));
    }

    if (_loading || _snapshot == null) {
      return widget.loading?.call(context) ??
          const Center(child: CircularProgressIndicator());
    }

    return widget.builder(context, _snapshot!);
  }
}
