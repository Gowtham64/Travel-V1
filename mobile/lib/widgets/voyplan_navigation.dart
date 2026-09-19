import 'package:flutter/material.dart';

/// The single source of truth for VoyPlan's primary navigation labels and
/// order. Page-specific headers supply their own actions while sharing this
/// customer-facing navigation vocabulary.
enum VoyPlanNavigationItem {
  home,
  planTrip,
  destinations,
  tripInspiration,
  myTrips,
  savedPlaces,
  features,
  aiCopilot,
}

extension VoyPlanNavigationItemDetails on VoyPlanNavigationItem {
  String get label => switch (this) {
        VoyPlanNavigationItem.home => 'Home',
        VoyPlanNavigationItem.planTrip => 'Plan Trip',
        VoyPlanNavigationItem.destinations => 'Destinations',
        VoyPlanNavigationItem.tripInspiration => 'Trip Inspiration',
        VoyPlanNavigationItem.myTrips => 'My Trips',
        VoyPlanNavigationItem.savedPlaces => 'Saved Places',
        VoyPlanNavigationItem.features => 'Features',
        VoyPlanNavigationItem.aiCopilot => 'AI Co-Pilot',
      };

  IconData get icon => switch (this) {
        VoyPlanNavigationItem.home => Icons.home_rounded,
        VoyPlanNavigationItem.planTrip => Icons.add_road_rounded,
        VoyPlanNavigationItem.destinations => Icons.explore_rounded,
        VoyPlanNavigationItem.tripInspiration => Icons.lightbulb_rounded,
        VoyPlanNavigationItem.myTrips => Icons.bookmark_rounded,
        VoyPlanNavigationItem.savedPlaces => Icons.favorite_rounded,
        VoyPlanNavigationItem.features => Icons.featured_play_list_rounded,
        VoyPlanNavigationItem.aiCopilot => Icons.auto_awesome_rounded,
      };
}

const voyPlanPrimaryNavigation = <VoyPlanNavigationItem>[
  VoyPlanNavigationItem.home,
  VoyPlanNavigationItem.planTrip,
  VoyPlanNavigationItem.destinations,
  VoyPlanNavigationItem.tripInspiration,
  VoyPlanNavigationItem.myTrips,
  VoyPlanNavigationItem.savedPlaces,
  VoyPlanNavigationItem.features,
  VoyPlanNavigationItem.aiCopilot,
];
