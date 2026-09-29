import 'package:flutter/material.dart';

/// Iconiță sugestivă pentru o categorie de venit/plată — afișată în lista de
/// tranzacții, lângă data/ora tranzacției. Fără categorie (ex. transfer),
/// se folosește [fallback].
IconData categoryIcon(String category, {IconData fallback = Icons.category}) {
  return _categoryIcons[category] ?? fallback;
}

const Map<String, IconData> _categoryIcons = {
  'Salariu': Icons.work_outline,
  'Cadou': Icons.card_giftcard,
  'Vânzare': Icons.sell_outlined,
  'Rambursare': Icons.replay,
  'Dobândă': Icons.percent,
  'Alte venituri': Icons.attach_money,
  'Mâncare': Icons.restaurant_outlined,
  'Transport': Icons.directions_car_outlined,
  'Facturi': Icons.receipt_long_outlined,
  'Chirie': Icons.home_outlined,
  'Sănătate': Icons.local_hospital_outlined,
  'Divertisment': Icons.movie_outlined,
  'Cumpărături': Icons.shopping_bag_outlined,
  'Alte plăți': Icons.more_horiz,
};

const List<String> incomeCategories = [
  'Salariu',
  'Cadou',
  'Vânzare',
  'Rambursare',
  'Dobândă',
  'Alte venituri',
];

const List<String> expenseCategories = [
  'Mâncare',
  'Transport',
  'Facturi',
  'Chirie',
  'Sănătate',
  'Divertisment',
  'Cumpărături',
  'Alte plăți',
];
