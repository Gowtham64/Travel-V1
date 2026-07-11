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
];

