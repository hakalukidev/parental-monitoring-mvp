abstract final class FormValidation {
  static String? email(String? value) => value == null ||
          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())
      ? 'Enter a valid email address'
      : null;
  static String? name(String? value) => value == null || value.trim().length < 2
      ? 'Enter at least two characters'
      : value.trim().length > 100
          ? 'Use 100 characters or fewer'
          : null;
  static String? password(String? value) => value == null || value.length < 8
      ? 'Use at least eight characters'
      : value.length > 128
          ? 'Use 128 characters or fewer'
          : null;
  static String? username(String? value) =>
      value == null || !RegExp(r'^[a-zA-Z0-9._-]{3,50}$').hasMatch(value.trim())
          ? 'Use 3–50 letters, numbers, dots, dashes or underscores'
          : null;
}
