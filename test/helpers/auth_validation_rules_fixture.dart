/// Minimal auth-related validation rules mirroring `functions/validation_rules.js`.
Map<String, dynamic> authValidationRulesFixture() => {
      'required': {'kind': 'required'},
      'email': {
        'kind': 'pattern',
        'required': true,
        'requiredField': 'Email',
        'pattern': r'^[\w.\-]+@([\w\-]+\.)+[\w\-]{2,}$',
        'invalidMessage': 'Enter a valid email address',
      },
      'optionalEmail': {
        'kind': 'optionalPattern',
        'pattern': r'^[\w.\-]+@([\w\-]+\.)+[\w\-]{2,}$',
        'invalidMessage': 'Enter a valid email address',
      },
      'phoneLocal': {
        'kind': 'phoneLocal',
        'required': true,
        'requiredField': 'Phone number',
        'defaultDialCode': '+91',
      },
      'password': {
        'kind': 'required',
        'requiredField': 'Password',
      },
      'confirmPassword': {
        'kind': 'confirmPassword',
        'requiredField': 'Confirm password',
      },
      'otp': {
        'kind': 'pattern',
        'required': true,
        'pattern': r'^\d{6}$',
        'invalidMessage': 'OTP must contain only digits',
        'length': 6,
        'lengthMessage': 'Enter the 6-digit OTP',
      },
      'loginUsername': {
        'kind': 'required',
        'requiredField': 'Username',
      },
    };
