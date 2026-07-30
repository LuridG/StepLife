import 'package:flutter_test/flutter_test.dart';
import 'package:steplife/core/utils/fitness_calculator.dart';

void main() {
  group('FitnessCalculator Tests', () {
    test('estimateStrideLength should return accurate stride length', () {
      final maleStride = FitnessCalculator.estimateStrideLength(heightCm: 175, gender: '男');
      expect(maleStride, closeTo(72.625, 0.001));

      final femaleStride = FitnessCalculator.estimateStrideLength(heightCm: 160, gender: '女');
      expect(femaleStride, closeTo(66.08, 0.001));
    });

    test('stepsToKilometers should calculate accurate distance', () {
      // 10,000 steps with 70cm stride = 7.00 km
      final km = FitnessCalculator.stepsToKilometers(10000, 70.0);
      expect(km, closeTo(7.0, 0.001));
    });

    test('calculateCalories should calculate MET-based calories', () {
      // 6,000 steps in 60 mins -> Cadence = 100 steps/min (MET=3.5)
      // Weight 70kg -> Calories = 3.5 * 70 * 1 = 245 kcal
      final kcal = FitnessCalculator.calculateCalories(
        steps: 6000,
        durationMinutes: 60,
        weightKg: 70.0,
      );
      expect(kcal, closeTo(245.0, 0.1));
    });
  });
}
