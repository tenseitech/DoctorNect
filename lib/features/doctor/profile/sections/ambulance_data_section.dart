import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../ambulance/data/ambulance_store.dart';
import '../../../ambulance/models/ambulance_models.dart';
import '../../../../core/theme/app_typography.dart';

class AmbulanceDataSection extends StatelessWidget {
  const AmbulanceDataSection({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ambulance Data'),
          bottom: TabBar(
            labelStyle:
                GoogleFonts.inter(fontSize: AppTypography.bodySmall, fontWeight: FontWeight.w600),
            unselectedLabelStyle:
                GoogleFonts.inter(fontSize: AppTypography.bodySmall, fontWeight: FontWeight.w400),
            indicatorColor: Colors.red[600],
            labelColor: Colors.red[600],
            unselectedLabelColor: Colors.grey[600],
            tabs: const [
              Tab(text: 'Providers'),
              Tab(text: 'Bookings'),
            ],
          ),
        ),
        body: ListenableBuilder(
          listenable: AmbulanceStore.instance,
          builder: (context, _) {
            final ambulances = AmbulanceStore.instance.registeredAmbulances;
            final bookings = AmbulanceStore.instance.bookings;
            return TabBarView(
              children: [
                _ProvidersTab(ambulances: ambulances),
                _BookingsTab(bookings: bookings),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Providers tab ─────────────────────────────────────────────────────────────

class _ProvidersTab extends StatelessWidget {
  const _ProvidersTab({required this.ambulances});
  final List<RegisteredAmbulance> ambulances;

  @override
  Widget build(BuildContext context) {
    if (ambulances.isEmpty) {
      return _EmptyState(
          icon: Icons.emergency_outlined,
          message: 'No ambulance providers registered.');
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          itemCount: ambulances.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _AmbulanceCard(amb: ambulances[i]),
        ),
      ),
    );
  }
}

class _AmbulanceCard extends StatelessWidget {
  const _AmbulanceCard({required this.amb});
  final RegisteredAmbulance amb;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.emergency_outlined,
                    color: Colors.red[600], size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(amb.serviceName,
                        style: GoogleFonts.inter(
                            fontSize: AppTypography.bodyMedium, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      '${amb.driverName}  •  ${amb.vehicleNumber}',
                      style: GoogleFonts.inter(
                          fontSize: AppTypography.labelSmall, color: Colors.grey[500]),
                    ),
                    Text(
                      amb.phone,
                      style: GoogleFonts.inter(
                          fontSize: AppTypography.labelSmall, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: amb.available
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      amb.available ? 'Available' : 'Unavailable',
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.labelSmall,
                        fontWeight: FontWeight.w600,
                        color: amb.available
                            ? AppColors.pharmacyGreen
                            : Colors.grey[500],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(amb.city,
                      style: GoogleFonts.inter(
                          fontSize: AppTypography.labelSmall, color: Colors.grey[400])),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _Chip(label: amb.ambulanceTypeLabel, color: Colors.red[600]!),
              if (amb.hasOxygen) _Chip(label: 'O₂', color: Colors.blue[600]!),
              if (amb.hasVentilator) _Chip(label: 'Ventilator', color: Colors.purple[600]!),
              if (amb.hasStretcher) _Chip(label: 'Stretcher', color: Colors.teal[600]!),
              if (amb.is24x7) _Chip(label: '24×7', color: Colors.orange[700]!),
              if (amb.ratePerKm != null) _Chip(label: '₹${amb.ratePerKm!.toStringAsFixed(0)}/km', color: Colors.green[700]!),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ── Bookings tab ──────────────────────────────────────────────────────────────

class _BookingsTab extends StatelessWidget {
  const _BookingsTab({required this.bookings});
  final List<AmbulanceBooking> bookings;

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty) {
      return _EmptyState(
          icon: Icons.local_taxi_outlined,
          message: 'No ambulance dispatch bookings yet.');
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          itemCount: bookings.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) => _BookingRow(booking: bookings[i]),
        ),
      ),
    );
  }
}

class _BookingRow extends StatelessWidget {
  const _BookingRow({required this.booking});
  final AmbulanceBooking booking;

  Color get _statusColor => switch (booking.status) {
        AmbulanceBookingStatus.pending => Colors.orange[600]!,
        AmbulanceBookingStatus.accepted => AppColors.pharmacyGreen,
        AmbulanceBookingStatus.cancelled => Colors.grey[500]!,
        AmbulanceBookingStatus.completed => const Color(0xFF0D9488),
      };

  String get _statusLabel => switch (booking.status) {
        AmbulanceBookingStatus.pending => 'Pending',
        AmbulanceBookingStatus.accepted => 'Accepted',
        AmbulanceBookingStatus.cancelled => 'Cancelled',
        AmbulanceBookingStatus.completed => 'Completed',
      };

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd MMM yyyy');
    final tf = DateFormat('hh:mm a');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.red[50],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.emergency_outlined,
                color: Colors.red[600], size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(booking.patientName,
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.bodySmall, fontWeight: FontWeight.w600)),
                Text(
                  booking.pickupLocation,
                  style: GoogleFonts.inter(
                      fontSize: AppTypography.labelSmall, color: Colors.grey[500]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 10, color: Colors.grey[400]),
                  const SizedBox(width: 4),
                  Text(
                    '${df.format(booking.createdAt)}  ${tf.format(booking.createdAt)}',
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.labelSmall, color: Colors.grey[500]),
                  ),
                ]),
                if (booking.acceptedAmbulanceName != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'By: ${booking.acceptedAmbulanceName}',
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.labelSmall,
                      color: AppColors.pharmacyGreen,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _statusLabel,
              style: GoogleFonts.inter(
                  fontSize: AppTypography.labelSmall,
                  fontWeight: FontWeight.w600,
                  color: _statusColor),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(message,
                style: GoogleFonts.inter(
                    fontSize: AppTypography.bodyMedium, color: Colors.grey[500])),
          ],
        ),
      );
}
