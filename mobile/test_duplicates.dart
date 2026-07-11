import 'lib/models/vehicles_data.dart';

void main() {
  var ids = <String>{};
  var names = <String>{};
  for (var v in predefinedVehicles) {
    if (!ids.add(v.id)) {
      print("Duplicate ID: ${v.id}");
    }
    if (!names.add(v.name)) {
      print("Duplicate Name: ${v.name}");
    }
  }
  print("Total distinct ids: ${ids.length}, total vehicles: ${predefinedVehicles.length}");
}
