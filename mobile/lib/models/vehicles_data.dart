class VehicleModel {
  final String id;
  final String name;
  final String type; // 'car' or 'motorcycle'
  final double mileage; // km/l
  final double tankCapacity; // Liters

  const VehicleModel({
    required this.id,
    required this.name,
    required this.type,
    required this.mileage,
    required this.tankCapacity,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VehicleModel &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// IDs of the two-wheelers that are scooters (step-through) rather than
/// motorcycles. Used to pick a scooter 3D model instead of the bike model.
const Set<String> kScooterIds = {
  'activa', 'dio', 'jupiter', 'ntorq', 'fascino', 'activa_125', 'access', 'burgman',
};

/// Finer-grained key for choosing the 3D vehicle model: distinguishes a
/// 'scooter' from a 'motorcycle'; otherwise returns the vehicle's own type.
String model3DKey(VehicleModel v) {
  if (v.type == 'motorcycle' && kScooterIds.contains(v.id)) return 'scooter';
  return v.type;
}

// Mileage values are realistic real-world/highway figures (deliberately a little
// below the optimistic ARAI lab numbers) so fuel/range estimates for a road trip
// don't fall short. Tank capacities are the model's actual fuel-tank sizes.
// Verified against CarWale/BikeWale/ZigWheels/CarDekho/Autocar India (2026).
const List<VehicleModel> predefinedVehicles = [
  // ── Motorcycles & scooters ────────────────────────────────────────────────
  VehicleModel(id: 'activa', name: 'Honda Activa 6G', type: 'motorcycle', mileage: 48.0, tankCapacity: 5.3),
  VehicleModel(id: 'classic350', name: 'Royal Enfield Classic 350', type: 'motorcycle', mileage: 35.0, tankCapacity: 13.0),
  VehicleModel(id: 'splendor', name: 'Hero Splendor Plus', type: 'motorcycle', mileage: 60.0, tankCapacity: 9.8),
  VehicleModel(id: 'pulsar150', name: 'Bajaj Pulsar 150', type: 'motorcycle', mileage: 45.0, tankCapacity: 14.0),
  VehicleModel(id: 'duke200', name: 'KTM Duke 200', type: 'motorcycle', mileage: 32.0, tankCapacity: 13.5),
  VehicleModel(id: 'bullet350', name: 'Royal Enfield Bullet 350', type: 'motorcycle', mileage: 37.0, tankCapacity: 13.0),
  VehicleModel(id: 'himalayan', name: 'Royal Enfield Himalayan', type: 'motorcycle', mileage: 30.0, tankCapacity: 17.0),
  VehicleModel(id: 'meteor350', name: 'Royal Enfield Meteor 350', type: 'motorcycle', mileage: 36.0, tankCapacity: 15.0),
  VehicleModel(id: 'hunter350', name: 'Royal Enfield Hunter 350', type: 'motorcycle', mileage: 36.0, tankCapacity: 13.0),
  VehicleModel(id: 'gt650', name: 'Royal Enfield Continental GT 650', type: 'motorcycle', mileage: 25.0, tankCapacity: 12.5),
  VehicleModel(id: 'r15', name: 'Yamaha YZF R15 V4', type: 'motorcycle', mileage: 45.0, tankCapacity: 11.0),
  VehicleModel(id: 'mt15', name: 'Yamaha MT-15 V2', type: 'motorcycle', mileage: 45.0, tankCapacity: 10.0),
  VehicleModel(id: 'fz25', name: 'Yamaha FZ25', type: 'motorcycle', mileage: 40.0, tankCapacity: 14.0),
  VehicleModel(id: 'apache160', name: 'TVS Apache RTR 160 4V', type: 'motorcycle', mileage: 45.0, tankCapacity: 12.0),
  VehicleModel(id: 'apache200', name: 'TVS Apache RTR 200 4V', type: 'motorcycle', mileage: 40.0, tankCapacity: 12.0),
  VehicleModel(id: 'ronin', name: 'TVS Ronin', type: 'motorcycle', mileage: 40.0, tankCapacity: 14.0),
  VehicleModel(id: 'dominar400', name: 'Bajaj Dominar 400', type: 'motorcycle', mileage: 27.0, tankCapacity: 13.0),
  VehicleModel(id: 'pulsar_n160', name: 'Bajaj Pulsar N160', type: 'motorcycle', mileage: 45.0, tankCapacity: 14.0),
  VehicleModel(id: 'pulsar220f', name: 'Bajaj Pulsar 220F', type: 'motorcycle', mileage: 38.0, tankCapacity: 15.0),
  VehicleModel(id: 'duke390', name: 'KTM Duke 390', type: 'motorcycle', mileage: 28.0, tankCapacity: 15.0),
  VehicleModel(id: 'cb350', name: 'Honda H\'ness CB350', type: 'motorcycle', mileage: 38.0, tankCapacity: 15.0),
  VehicleModel(id: 'unicorn', name: 'Honda Unicorn', type: 'motorcycle', mileage: 50.0, tankCapacity: 13.0),
  VehicleModel(id: 'xtreme160r', name: 'Hero Xtreme 160R', type: 'motorcycle', mileage: 45.0, tankCapacity: 12.0),
  VehicleModel(id: 'interceptor650', name: 'Royal Enfield Interceptor 650', type: 'motorcycle', mileage: 25.0, tankCapacity: 13.7),
  VehicleModel(id: 'dio', name: 'Honda Dio', type: 'motorcycle', mileage: 48.0, tankCapacity: 5.3),
  VehicleModel(id: 'jupiter', name: 'TVS Jupiter 125', type: 'motorcycle', mileage: 50.0, tankCapacity: 5.1),
  VehicleModel(id: 'ntorq', name: 'TVS Ntorq 125', type: 'motorcycle', mileage: 42.0, tankCapacity: 5.8),
  VehicleModel(id: 'fz_s_fi', name: 'Yamaha FZ-S FI', type: 'motorcycle', mileage: 45.0, tankCapacity: 13.0),
  VehicleModel(id: 'ray_zr', name: 'Yamaha Ray ZR', type: 'motorcycle', mileage: 50.0, tankCapacity: 5.2),
  VehicleModel(id: 'fascino', name: 'Yamaha Fascino 125', type: 'motorcycle', mileage: 50.0, tankCapacity: 5.2),
  VehicleModel(id: 'activa_125', name: 'Honda Activa 125', type: 'motorcycle', mileage: 47.0, tankCapacity: 5.3),
  VehicleModel(id: 'shine', name: 'Honda Shine', type: 'motorcycle', mileage: 55.0, tankCapacity: 10.5),
  VehicleModel(id: 'sp_125', name: 'Honda SP 125', type: 'motorcycle', mileage: 58.0, tankCapacity: 11.0),
  VehicleModel(id: 'hf_deluxe', name: 'Hero HF Deluxe', type: 'motorcycle', mileage: 63.0, tankCapacity: 9.6),
  VehicleModel(id: 'glamour', name: 'Hero Glamour', type: 'motorcycle', mileage: 55.0, tankCapacity: 10.0),
  VehicleModel(id: 'pulsar_ns200', name: 'Bajaj Pulsar NS200', type: 'motorcycle', mileage: 35.0, tankCapacity: 12.0),
  VehicleModel(id: 'platina', name: 'Bajaj Platina 100', type: 'motorcycle', mileage: 68.0, tankCapacity: 11.0),
  VehicleModel(id: 'access', name: 'Suzuki Access 125', type: 'motorcycle', mileage: 45.0, tankCapacity: 5.0),
  VehicleModel(id: 'burgman', name: 'Suzuki Burgman Street', type: 'motorcycle', mileage: 45.0, tankCapacity: 5.5),
  VehicleModel(id: 'gixxer', name: 'Suzuki Gixxer', type: 'motorcycle', mileage: 45.0, tankCapacity: 12.0),
  VehicleModel(id: 'gixxer_sf', name: 'Suzuki Gixxer SF', type: 'motorcycle', mileage: 45.0, tankCapacity: 12.0),

  // ── Cars ──────────────────────────────────────────────────────────────────
  VehicleModel(id: 'swift', name: 'Maruti Suzuki Swift', type: 'car', mileage: 20.0, tankCapacity: 37.0),
  VehicleModel(id: 'baleno', name: 'Maruti Suzuki Baleno', type: 'car', mileage: 21.0, tankCapacity: 37.0),
  VehicleModel(id: 'wagonr', name: 'Maruti Suzuki Wagon R', type: 'car', mileage: 21.0, tankCapacity: 32.0),
  VehicleModel(id: 'ertiga', name: 'Maruti Suzuki Ertiga', type: 'car', mileage: 18.0, tankCapacity: 45.0),
  VehicleModel(id: 'dzire', name: 'Maruti Suzuki Dzire', type: 'car', mileage: 21.0, tankCapacity: 37.0),
  VehicleModel(id: 'alto', name: 'Maruti Suzuki Alto K10', type: 'car', mileage: 20.0, tankCapacity: 27.0),
  VehicleModel(id: 'celerio', name: 'Maruti Suzuki Celerio', type: 'car', mileage: 22.0, tankCapacity: 32.0),
  VehicleModel(id: 'brezza', name: 'Maruti Suzuki Brezza', type: 'car', mileage: 16.0, tankCapacity: 48.0),
  VehicleModel(id: 'grand_vitara', name: 'Maruti Suzuki Grand Vitara', type: 'car', mileage: 19.0, tankCapacity: 45.0),
  VehicleModel(id: 'fronx', name: 'Maruti Suzuki Fronx', type: 'car', mileage: 18.0, tankCapacity: 37.0),
  VehicleModel(id: 'ciaz', name: 'Maruti Suzuki Ciaz', type: 'car', mileage: 18.0, tankCapacity: 43.0),
  VehicleModel(id: 'xl6', name: 'Maruti Suzuki XL6', type: 'car', mileage: 17.0, tankCapacity: 45.0),
  VehicleModel(id: 'innova', name: 'Toyota Innova Crysta', type: 'car', mileage: 12.0, tankCapacity: 55.0),
  VehicleModel(id: 'hycross', name: 'Toyota Innova Hycross', type: 'car', mileage: 15.0, tankCapacity: 52.0),
  VehicleModel(id: 'glanza', name: 'Toyota Glanza', type: 'car', mileage: 21.0, tankCapacity: 37.0),
  VehicleModel(id: 'hyryder', name: 'Toyota Urban Cruiser Hyryder', type: 'car', mileage: 18.0, tankCapacity: 45.0),
  VehicleModel(id: 'fortuner', name: 'Toyota Fortuner', type: 'car', mileage: 11.0, tankCapacity: 80.0),
  VehicleModel(id: 'creta', name: 'Hyundai Creta', type: 'car', mileage: 16.0, tankCapacity: 50.0),
  VehicleModel(id: 'i20', name: 'Hyundai i20', type: 'car', mileage: 18.0, tankCapacity: 37.0),
  VehicleModel(id: 'venue', name: 'Hyundai Venue', type: 'car', mileage: 16.0, tankCapacity: 45.0),
  VehicleModel(id: 'verna', name: 'Hyundai Verna', type: 'car', mileage: 17.0, tankCapacity: 45.0),
  VehicleModel(id: 'aura', name: 'Hyundai Aura', type: 'car', mileage: 18.0, tankCapacity: 37.0),
  VehicleModel(id: 'exter', name: 'Hyundai Exter', type: 'car', mileage: 17.0, tankCapacity: 37.0),
  VehicleModel(id: 'alcazar', name: 'Hyundai Alcazar', type: 'car', mileage: 14.0, tankCapacity: 50.0),
  VehicleModel(id: 'seltos', name: 'Kia Seltos', type: 'car', mileage: 15.0, tankCapacity: 50.0),
  VehicleModel(id: 'sonet', name: 'Kia Sonet', type: 'car', mileage: 16.0, tankCapacity: 45.0),
  VehicleModel(id: 'carens', name: 'Kia Carens', type: 'car', mileage: 14.0, tankCapacity: 45.0),
  VehicleModel(id: 'nexon', name: 'Tata Nexon', type: 'car', mileage: 16.0, tankCapacity: 44.0),
  VehicleModel(id: 'punch', name: 'Tata Punch', type: 'car', mileage: 17.0, tankCapacity: 37.0),
  VehicleModel(id: 'tiago', name: 'Tata Tiago', type: 'car', mileage: 17.0, tankCapacity: 35.0),
  VehicleModel(id: 'tigor', name: 'Tata Tigor', type: 'car', mileage: 17.0, tankCapacity: 35.0),
  VehicleModel(id: 'altroz', name: 'Tata Altroz', type: 'car', mileage: 17.0, tankCapacity: 37.0),
  VehicleModel(id: 'harrier', name: 'Tata Harrier', type: 'car', mileage: 14.0, tankCapacity: 50.0),
  VehicleModel(id: 'safari', name: 'Tata Safari', type: 'car', mileage: 14.0, tankCapacity: 50.0),
  VehicleModel(id: 'xuv700', name: 'Mahindra XUV700', type: 'car', mileage: 13.0, tankCapacity: 60.0),
  VehicleModel(id: 'scorpio_n', name: 'Mahindra Scorpio-N', type: 'car', mileage: 13.0, tankCapacity: 57.0),
  VehicleModel(id: 'scorpio_classic', name: 'Mahindra Scorpio Classic', type: 'car', mileage: 13.0, tankCapacity: 60.0),
  VehicleModel(id: 'thar', name: 'Mahindra Thar', type: 'car', mileage: 13.0, tankCapacity: 57.0),
  VehicleModel(id: 'bolero', name: 'Mahindra Bolero', type: 'car', mileage: 15.0, tankCapacity: 60.0),
  VehicleModel(id: 'xuv300', name: 'Mahindra XUV300', type: 'car', mileage: 15.0, tankCapacity: 42.0),
  VehicleModel(id: 'city', name: 'Honda City', type: 'car', mileage: 16.0, tankCapacity: 40.0),
  VehicleModel(id: 'amaze', name: 'Honda Amaze', type: 'car', mileage: 17.0, tankCapacity: 35.0),
  VehicleModel(id: 'kushaq', name: 'Skoda Kushaq', type: 'car', mileage: 15.0, tankCapacity: 50.0),
  VehicleModel(id: 'slavia', name: 'Skoda Slavia', type: 'car', mileage: 16.0, tankCapacity: 45.0),
  VehicleModel(id: 'virtus', name: 'Volkswagen Virtus', type: 'car', mileage: 16.0, tankCapacity: 45.0),
  VehicleModel(id: 'taigun', name: 'Volkswagen Taigun', type: 'car', mileage: 15.0, tankCapacity: 50.0),
  VehicleModel(id: 'astor', name: 'MG Astor', type: 'car', mileage: 13.0, tankCapacity: 45.0),
  VehicleModel(id: 'hector', name: 'MG Hector', type: 'car', mileage: 12.0, tankCapacity: 60.0),
  VehicleModel(id: 'compass', name: 'Jeep Compass', type: 'car', mileage: 12.0, tankCapacity: 60.0),
  VehicleModel(id: 'magnite', name: 'Nissan Magnite', type: 'car', mileage: 17.0, tankCapacity: 40.0),
  VehicleModel(id: 'kiger', name: 'Renault Kiger', type: 'car', mileage: 17.0, tankCapacity: 40.0),
  VehicleModel(id: 'triber', name: 'Renault Triber', type: 'car', mileage: 16.0, tankCapacity: 40.0),
  VehicleModel(id: 'kwid', name: 'Renault Kwid', type: 'car', mileage: 19.0, tankCapacity: 28.0),

  // ── Custom (user-editable) ──────────────────────────────────────────────
  VehicleModel(id: 'custom_car', name: 'Custom Car', type: 'car', mileage: 15.0, tankCapacity: 45.0),
  VehicleModel(id: 'custom_bike', name: 'Custom Bike', type: 'motorcycle', mileage: 40.0, tankCapacity: 12.0),
];
