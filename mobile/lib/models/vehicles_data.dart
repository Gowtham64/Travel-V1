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

const List<VehicleModel> predefinedVehicles = [
  // Bikes
  VehicleModel(id: 'activa', name: 'Honda Activa 6G', type: 'motorcycle', mileage: 45.0, tankCapacity: 5.3),
  VehicleModel(id: 'classic350', name: 'Royal Enfield Classic 350', type: 'motorcycle', mileage: 35.0, tankCapacity: 13.0),
  VehicleModel(id: 'splendor', name: 'Hero Splendor Plus', type: 'motorcycle', mileage: 60.0, tankCapacity: 9.8),
  VehicleModel(id: 'pulsar150', name: 'Bajaj Pulsar 150', type: 'motorcycle', mileage: 45.0, tankCapacity: 15.0),
  VehicleModel(id: 'duke200', name: 'KTM Duke 200', type: 'motorcycle', mileage: 33.0, tankCapacity: 13.4),
  VehicleModel(id: 'bullet350', name: 'Royal Enfield Bullet 350', type: 'motorcycle', mileage: 38.0, tankCapacity: 13.5),
  VehicleModel(id: 'himalayan', name: 'Royal Enfield Himalayan', type: 'motorcycle', mileage: 30.0, tankCapacity: 15.0),
  VehicleModel(id: 'meteor350', name: 'Royal Enfield Meteor 350', type: 'motorcycle', mileage: 36.0, tankCapacity: 15.0),
  VehicleModel(id: 'r15', name: 'Yamaha YZF R15 V4', type: 'motorcycle', mileage: 45.0, tankCapacity: 11.0),
  VehicleModel(id: 'mt15', name: 'Yamaha MT-15 V2', type: 'motorcycle', mileage: 48.0, tankCapacity: 10.0),
  VehicleModel(id: 'apache160', name: 'TVS Apache RTR 160 4V', type: 'motorcycle', mileage: 45.0, tankCapacity: 12.0),
  VehicleModel(id: 'ronin', name: 'TVS Ronin', type: 'motorcycle', mileage: 40.0, tankCapacity: 14.0),
  VehicleModel(id: 'dominar400', name: 'Bajaj Dominar 400', type: 'motorcycle', mileage: 27.0, tankCapacity: 13.0),
  VehicleModel(id: 'cb350', name: 'Honda H\'ness CB350', type: 'motorcycle', mileage: 35.0, tankCapacity: 15.0),
  VehicleModel(id: 'interceptor650', name: 'Royal Enfield Interceptor 650', type: 'motorcycle', mileage: 23.0, tankCapacity: 13.7),
  VehicleModel(id: 'dio', name: 'Honda Dio', type: 'motorcycle', mileage: 48.0, tankCapacity: 5.3),
  VehicleModel(id: 'jupiter', name: 'TVS Jupiter 125', type: 'motorcycle', mileage: 50.0, tankCapacity: 5.1),
  VehicleModel(id: 'ntorq', name: 'TVS Ntorq 125', type: 'motorcycle', mileage: 42.0, tankCapacity: 5.8),

  // Cars
  VehicleModel(id: 'swift', name: 'Maruti Suzuki Swift', type: 'car', mileage: 22.0, tankCapacity: 37.0),
  VehicleModel(id: 'baleno', name: 'Maruti Suzuki Baleno', type: 'car', mileage: 22.3, tankCapacity: 37.0),
  VehicleModel(id: 'wagonr', name: 'Maruti Suzuki Wagon R', type: 'car', mileage: 24.0, tankCapacity: 32.0),
  VehicleModel(id: 'ertiga', name: 'Maruti Suzuki Ertiga', type: 'car', mileage: 20.5, tankCapacity: 45.0),
  VehicleModel(id: 'innova', name: 'Toyota Innova Crysta', type: 'car', mileage: 11.0, tankCapacity: 65.0),
  VehicleModel(id: 'glanza', name: 'Toyota Glanza', type: 'car', mileage: 22.3, tankCapacity: 37.0),
  VehicleModel(id: 'fortuner', name: 'Toyota Fortuner', type: 'car', mileage: 10.0, tankCapacity: 80.0),
  VehicleModel(id: 'creta', name: 'Hyundai Creta', type: 'car', mileage: 16.8, tankCapacity: 50.0),
  VehicleModel(id: 'i20', name: 'Hyundai i20', type: 'car', mileage: 20.0, tankCapacity: 37.0),
  VehicleModel(id: 'venue', name: 'Hyundai Venue', type: 'car', mileage: 17.5, tankCapacity: 45.0),
  VehicleModel(id: 'seltos', name: 'Kia Seltos', type: 'car', mileage: 16.5, tankCapacity: 50.0),
  VehicleModel(id: 'sonet', name: 'Kia Sonet', type: 'car', mileage: 18.0, tankCapacity: 45.0),
  VehicleModel(id: 'nexon', name: 'Tata Nexon', type: 'car', mileage: 17.0, tankCapacity: 44.0),
  VehicleModel(id: 'harrier', name: 'Tata Harrier', type: 'car', mileage: 16.0, tankCapacity: 50.0),
  VehicleModel(id: 'punch', name: 'Tata Punch', type: 'car', mileage: 18.8, tankCapacity: 37.0),
  VehicleModel(id: 'xuv700', name: 'Mahindra XUV700', type: 'car', mileage: 13.0, tankCapacity: 60.0),
  VehicleModel(id: 'scorpio_n', name: 'Mahindra Scorpio-N', type: 'car', mileage: 14.0, tankCapacity: 57.0),
  VehicleModel(id: 'thar', name: 'Mahindra Thar', type: 'car', mileage: 15.0, tankCapacity: 57.0),
  VehicleModel(id: 'city', name: 'Honda City', type: 'car', mileage: 17.8, tankCapacity: 40.0),
  VehicleModel(id: 'amaze', name: 'Honda Amaze', type: 'car', mileage: 18.3, tankCapacity: 35.0),
  
  // Custom
  VehicleModel(id: 'custom_car', name: 'Custom Car', type: 'car', mileage: 15.0, tankCapacity: 45.0),
  VehicleModel(id: 'custom_bike', name: 'Custom Bike', type: 'motorcycle', mileage: 40.0, tankCapacity: 12.0),

  // Additional Popular Motorcycles
  VehicleModel(id: 'fz_s_fi', name: 'Yamaha FZ-S FI', type: 'motorcycle', mileage: 45.0, tankCapacity: 13.0),
  VehicleModel(id: 'ray_zr', name: 'Yamaha Ray ZR', type: 'motorcycle', mileage: 52.0, tankCapacity: 5.2),
  VehicleModel(id: 'fascino', name: 'Yamaha Fascino 125', type: 'motorcycle', mileage: 50.0, tankCapacity: 5.2),
  VehicleModel(id: 'activa_125', name: 'Honda Activa 125', type: 'motorcycle', mileage: 47.0, tankCapacity: 5.3),
  VehicleModel(id: 'shine', name: 'Honda Shine', type: 'motorcycle', mileage: 55.0, tankCapacity: 10.5),
  VehicleModel(id: 'sp_125', name: 'Honda SP 125', type: 'motorcycle', mileage: 60.0, tankCapacity: 11.0),
  VehicleModel(id: 'hf_deluxe', name: 'Hero HF Deluxe', type: 'motorcycle', mileage: 65.0, tankCapacity: 9.6),
  VehicleModel(id: 'glamour', name: 'Hero Glamour', type: 'motorcycle', mileage: 55.0, tankCapacity: 10.0),
  VehicleModel(id: 'pulsar_ns200', name: 'Bajaj Pulsar NS200', type: 'motorcycle', mileage: 35.0, tankCapacity: 12.0),
  VehicleModel(id: 'platina', name: 'Bajaj Platina 100', type: 'motorcycle', mileage: 70.0, tankCapacity: 11.0),
  VehicleModel(id: 'access', name: 'Suzuki Access 125', type: 'motorcycle', mileage: 45.0, tankCapacity: 5.0),
  VehicleModel(id: 'burgman', name: 'Suzuki Burgman Street', type: 'motorcycle', mileage: 48.0, tankCapacity: 5.5),
  VehicleModel(id: 'gixxer', name: 'Suzuki Gixxer', type: 'motorcycle', mileage: 45.0, tankCapacity: 12.0),

  // Additional Popular Cars
  VehicleModel(id: 'alto', name: 'Maruti Suzuki Alto 800', type: 'car', mileage: 22.0, tankCapacity: 35.0),
  VehicleModel(id: 'dzire', name: 'Maruti Suzuki Dzire', type: 'car', mileage: 23.0, tankCapacity: 37.0),
  VehicleModel(id: 'brezza', name: 'Maruti Suzuki Brezza', type: 'car', mileage: 19.8, tankCapacity: 48.0),
  VehicleModel(id: 'grand_vitara', name: 'Maruti Suzuki Grand Vitara', type: 'car', mileage: 21.1, tankCapacity: 45.0),
  VehicleModel(id: 'tiago', name: 'Tata Tiago', type: 'car', mileage: 19.0, tankCapacity: 35.0),
  VehicleModel(id: 'altroz', name: 'Tata Altroz', type: 'car', mileage: 18.5, tankCapacity: 37.0),
  VehicleModel(id: 'safari', name: 'Tata Safari', type: 'car', mileage: 14.0, tankCapacity: 50.0),
  VehicleModel(id: 'bolero', name: 'Mahindra Bolero', type: 'car', mileage: 16.0, tankCapacity: 60.0),
  VehicleModel(id: 'xuv300', name: 'Mahindra XUV300', type: 'car', mileage: 17.0, tankCapacity: 42.0),
  VehicleModel(id: 'carens', name: 'Kia Carens', type: 'car', mileage: 16.0, tankCapacity: 45.0),
  VehicleModel(id: 'verna', name: 'Hyundai Verna', type: 'car', mileage: 18.6, tankCapacity: 45.0),
  VehicleModel(id: 'aura', name: 'Hyundai Aura', type: 'car', mileage: 20.5, tankCapacity: 37.0),
  VehicleModel(id: 'magnite', name: 'Nissan Magnite', type: 'car', mileage: 18.7, tankCapacity: 40.0),
  VehicleModel(id: 'kiger', name: 'Renault Kiger', type: 'car', mileage: 19.0, tankCapacity: 40.0),
  VehicleModel(id: 'triber', name: 'Renault Triber', type: 'car', mileage: 18.2, tankCapacity: 40.0),
  VehicleModel(id: 'kwid', name: 'Renault Kwid', type: 'car', mileage: 21.0, tankCapacity: 28.0),
];
