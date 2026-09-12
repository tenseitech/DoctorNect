/** Declarative validation rules — single source of truth for Medibond forms. */

const DEFAULT_DIAL_CODE = '+91';

const RULES = {
  required: {
    kind: 'required',
  },
  fullName: {
    kind: 'pattern',
    required: true,
    requiredField: 'Full name',
    pattern: '^[a-zA-Z\\s]{2,}$',
    invalidMessage: 'Enter a valid full name',
  },
  email: {
    kind: 'pattern',
    required: true,
    requiredField: 'Email',
    pattern: '^[\\w.\\-]+@([\\w\\-]+\\.)+[\\w\\-]{2,}$',
    invalidMessage: 'Enter a valid email address',
  },
  optionalEmail: {
    kind: 'optionalPattern',
    pattern: '^[\\w.\\-]+@([\\w\\-]+\\.)+[\\w\\-]{2,}$',
    invalidMessage: 'Enter a valid email address',
  },
  phoneLocal: {
    kind: 'phoneLocal',
    required: true,
    requiredField: 'Phone number',
    defaultDialCode: DEFAULT_DIAL_CODE,
  },
  password: {
    kind: 'required',
    requiredField: 'Password',
  },
  confirmPassword: {
    kind: 'confirmPassword',
    requiredField: 'Confirm password',
  },
  pincode: {
    kind: 'pattern',
    required: true,
    requiredField: 'Pincode',
    pattern: '^\\d{6}$',
    invalidMessage: 'Enter a valid 6-digit pincode',
  },
  age: {
    kind: 'intRange',
    required: true,
    requiredField: 'Age',
    min: 1,
    max: 120,
    invalidMessage: 'Enter a valid age',
    rangeMessage: 'Enter a valid age ({min}–{max})',
  },
  experience: {
    kind: 'intRange',
    required: true,
    requiredField: 'Years of experience',
    min: 0,
    max: 60,
    invalidMessage: 'Enter valid years (0–60)',
  },
  consultationDuration: {
    kind: 'intRange',
    required: true,
    requiredField: 'Consultation duration',
    min: 5,
    max: 480,
    invalidMessage: 'Minimum duration is 5 minutes',
  },
  reminderHours: {
    kind: 'intRange',
    required: true,
    requiredField: 'Reminder time',
    min: 1,
    max: 24,
    invalidMessage: 'Enter hours between 1 and 24',
  },
  councilNumber: {
    kind: 'minLength',
    required: true,
    requiredField: 'Registration number',
    minLength: 4,
    invalidMessage: 'Enter a valid registration number',
  },
  vehicleNumber: {
    kind: 'vehicleNumber',
    required: true,
    requiredField: 'Vehicle number',
  },
  otp: {
    kind: 'pattern',
    required: true,
    pattern: '^\\d{6}$',
    invalidMessage: 'OTP must contain only digits',
    length: 6,
    lengthMessage: 'Enter the 6-digit OTP',
  },
  dropdown: {
    kind: 'dropdown',
  },
  file: {
    kind: 'file',
  },
  multiSelect: {
    kind: 'multiSelect',
  },
  bloodPressure: {
    kind: 'bloodPressure',
  },
  temperature: {
    kind: 'optionalNumeric',
    label: 'temperature',
    min: 90,
    max: 150,
  },
  pulse: {
    kind: 'optionalNumeric',
    label: 'pulse',
    min: 20,
    max: 250,
  },
  spo2: {
    kind: 'optionalNumeric',
    label: 'SpO2',
    min: 50,
    max: 100,
  },
  respiratoryRate: {
    kind: 'optionalNumeric',
    label: 'respiratory rate',
    min: 4,
    max: 60,
  },
  username: {
    kind: 'pattern',
    required: true,
    requiredField: 'Username',
    minLength: 3,
    minLengthMessage: 'Username must be at least 3 characters',
    pattern: '^[a-zA-Z0-9_\\.]+$',
    invalidMessage: 'Only letters, numbers, underscores and dots allowed',
  },
  securityPin: {
    kind: 'pattern',
    required: true,
    requiredField: 'PIN',
    pattern: '^\\d{6}$',
    length: 6,
    lengthMessage: 'PIN must be exactly 6 digits',
    invalidMessage: 'PIN must be 6 digits',
  },
  confirmSecurityPin: {
    kind: 'confirmPassword',
    requiredField: 'Confirm PIN',
  },
  walkInAge: {
    kind: 'intRange',
    required: true,
    requiredField: 'Age',
    min: 1,
    max: 150,
    invalidMessage: 'Invalid age',
  },
  patientName: {
    kind: 'required',
    requiredField: 'Patient name',
  },
  primaryDiagnosis: {
    kind: 'required',
    requiredField: 'Primary diagnosis',
  },
  tagText: {
    kind: 'minLength',
    required: true,
    minLength: 2,
    maxLength: 50,
    invalidMessage: 'Enter at least 2 characters',
    maxLengthMessage: 'Maximum 50 characters',
  },
  helpMessage: {
    kind: 'minLength',
    required: true,
    requiredField: 'Message',
    minLength: 20,
    invalidMessage: 'Enter at least 20 characters',
  },
  maxAppointments: {
    kind: 'intRange',
    required: true,
    requiredField: 'Maximum appointments',
    min: 1,
    max: 5000,
    invalidMessage: 'Enter 1–5000',
  },
  currentPassword: {
    kind: 'required',
    requiredField: 'Current password',
  },
  newPassword: {
    kind: 'minLength',
    required: true,
    requiredField: 'New password',
    minLength: 6,
    invalidMessage: 'Password must be at least 6 characters',
  },
  confirmNewPassword: {
    kind: 'confirmPassword',
    requiredField: 'Confirm password',
  },
  changePassword: {
    kind: 'changePassword',
    required: true,
    requiredField: 'New password',
    minLength: 6,
    invalidMessage: 'Password must be at least 6 characters',
    sameAsMessage: 'New password must differ from current',
  },
  loginUsername: {
    kind: 'required',
    requiredField: 'Username',
  },
  loginSecurityPin: {
    kind: 'pattern',
    required: true,
    requiredField: 'Security PIN',
    pattern: '^\\d{6}$',
    length: 6,
    lengthMessage: 'PIN must be 6 digits',
    invalidMessage: 'PIN must be 6 digits',
  },
};

const VEHICLE_NUMBER_PATTERNS = [
  '^[A-Z]{2}[0-9]{1,2}[A-Z]{1,3}[0-9]{1,4}$',
  '^[0-9]{2}BH[0-9]{4}[A-Z]{2}$',
];

RULES.vehicleNumber.patterns = VEHICLE_NUMBER_PATTERNS;
RULES.vehicleNumber.invalidMessage =
  'Enter a valid vehicle number (e.g. MH-12-AB-4521)';

const BLOOD_PRESSURE_RULE = {
  formatPattern: '^(\\d{2,3})/(\\d{2,3})$',
  formatMessage: 'Enter BP as systolic/diastolic (e.g. 120/80)',
  invalidMessage: 'Enter a valid blood pressure',
  orderMessage: 'Systolic BP must be higher than diastolic BP',
  plausibleMessage: 'Enter a plausible blood pressure',
  sysMin: 50,
  sysMax: 250,
  diaMin: 30,
  diaMax: 150,
};

RULES.bloodPressure = { kind: 'bloodPressure', ...BLOOD_PRESSURE_RULE };

const VITAL_THRESHOLDS = {
  bloodPressure: {
    criticalSysLow: 80,
    criticalSysHigh: 180,
    normalSysMin: 90,
    normalSysMax: 120,
    normalDiaMin: 60,
    normalDiaMax: 80,
  },
  temperature: {
    hypothermia: 95,
    belowNormal: 97,
    normalMax: 99,
    lowGradeFever: 100.3,
    fever: 103,
    highFever: 105,
  },
  pulse: {
    normalMin: 60,
    normalMax: 100,
    criticalLow: 40,
    criticalHigh: 150,
  },
  spo2: {
    critical: 85,
    emergency: 90,
    cautionMin: 91,
    normalMin: 95,
    normalMax: 100,
  },
  respiratoryRate: {
    normalMin: 12,
    normalMax: 20,
    criticalLow: 8,
    criticalHigh: 30,
  },
};

function requiredMessage(field) {
  return `${field} is required`;
}

function normalizeIndianMobileDigits(digits) {
  let normalized = String(digits || '').replace(/\D/g, '');
  if (normalized.length === 12 && normalized.startsWith('91')) {
    normalized = normalized.substring(2);
  } else if (normalized.length === 11 && normalized.startsWith('0')) {
    normalized = normalized.substring(1);
  }
  if (normalized.length !== 10 || !/^[6-9]/.test(normalized)) {
    return null;
  }
  return normalized;
}

function normalizeVehicleNumber(value) {
  return String(value || '').replace(/[\s\-]/g, '').toUpperCase();
}

function runRule(ruleName, value, params = {}) {
  const rule = RULES[ruleName];
  if (!rule) {
    return { error: `Unknown validation rule: ${ruleName}` };
  }

  const field = params.field || rule.requiredField || 'This field';
  const str = value == null ? '' : String(value).trim();

  switch (rule.kind) {
    case 'required':
      if (str.length === 0) return { error: requiredMessage(field) };
      return { error: null };

    case 'pattern': {
      if (str.length === 0) {
        return { error: requiredMessage(rule.requiredField || field) };
      }
      if (rule.minLength != null && str.length < rule.minLength) {
        return { error: rule.minLengthMessage || rule.invalidMessage };
      }
      if (rule.length != null && str.length !== rule.length) {
        return { error: rule.lengthMessage || rule.invalidMessage };
      }
      const re = new RegExp(rule.pattern);
      if (!re.test(str)) return { error: rule.invalidMessage };
      return { error: null };
    }

    case 'optionalPattern': {
      if (str.length === 0) return { error: null };
      const re = new RegExp(rule.pattern);
      if (!re.test(str)) return { error: rule.invalidMessage };
      return { error: null };
    }

    case 'phoneLocal': {
      if (str.length === 0) {
        return { error: requiredMessage(rule.requiredField || field) };
      }
      const dialCode = params.dialCode || rule.defaultDialCode || DEFAULT_DIAL_CODE;
      const digits = str.replace(/\D/g, '');
      if (dialCode === DEFAULT_DIAL_CODE) {
        if (!normalizeIndianMobileDigits(digits)) {
          return { error: 'Enter a valid 10-digit mobile number' };
        }
        return { error: null };
      }
      if (digits.length < 4 || digits.length > 15) {
        return { error: 'Enter a valid phone number' };
      }
      return { error: null };
    }

    case 'confirmPassword': {
      if (str.length === 0) {
        return { error: requiredMessage(rule.requiredField || field) };
      }
      if (str !== String(params.password || '')) {
        return { error: 'Passwords do not match' };
      }
      return { error: null };
    }

    case 'changePassword': {
      if (str.length === 0) {
        return { error: requiredMessage(rule.requiredField || field) };
      }
      if (str.length < (rule.minLength || 6)) {
        return { error: rule.invalidMessage };
      }
      if (str === String(params.current || '')) {
        return { error: rule.sameAsMessage || 'New password must differ from current' };
      }
      return { error: null };
    }

    case 'intRange': {
      if (str.length === 0) {
        return { error: requiredMessage(rule.requiredField || field) };
      }
      if (!/^\d{1,3}$/.test(str) && ruleName === 'age') {
        return { error: rule.invalidMessage };
      }
      const n = Number.parseInt(str, 10);
      const min = params.min ?? rule.min;
      const max = params.max ?? rule.max;
      if (Number.isNaN(n) || n < min || n > max) {
        const msg = (rule.rangeMessage || rule.invalidMessage || '').replace('{min}', min).replace('{max}', max);
        return { error: msg };
      }
      return { error: null };
    }

    case 'minLength': {
      if (str.length === 0) {
        return { error: requiredMessage(rule.requiredField || field) };
      }
      if (str.length < (rule.minLength || 1)) {
        return { error: rule.invalidMessage };
      }
      if (rule.maxLength != null && str.length > rule.maxLength) {
        return { error: rule.maxLengthMessage || rule.invalidMessage };
      }
      return { error: null };
    }

    case 'vehicleNumber': {
      if (str.length === 0) {
        return { error: requiredMessage(rule.requiredField || field) };
      }
      const normalized = normalizeVehicleNumber(str);
      const patterns = rule.patterns || VEHICLE_NUMBER_PATTERNS;
      const matched = patterns.some((p) => new RegExp(p).test(normalized));
      if (!matched) {
        return { error: rule.invalidMessage || 'Enter a valid vehicle number' };
      }
      return { error: null };
    }

    case 'dropdown': {
      if (value == null || String(value).length === 0) {
        return { error: `Please select ${field}` };
      }
      return { error: null };
    }

    case 'file': {
      if (value == null || String(value).length === 0) {
        return { error: `Please upload ${field}` };
      }
      return { error: null };
    }

    case 'multiSelect': {
      const selected = params.selected;
      const count = Array.isArray(selected)
        ? selected.length
        : selected instanceof Set
          ? selected.size
          : 0;
      if (count === 0) {
        return { error: `Please select at least one ${field}` };
      }
      return { error: null };
    }

    case 'optionalNumeric': {
      if (str.length === 0) return { error: null };
      const parsed = Number.parseFloat(str);
      if (Number.isNaN(parsed)) {
        return { error: `Enter a valid ${rule.label}` };
      }
      if (parsed < rule.min) return { error: `${rule.label} is too low` };
      if (parsed > rule.max) return { error: `${rule.label} is too high` };
      return { error: null };
    }

    case 'bloodPressure': {
      if (str.length === 0) return { error: null };
      const bpRule = { ...BLOOD_PRESSURE_RULE, ...rule };
      const match = new RegExp(bpRule.formatPattern).exec(str);
      if (!match) {
        return { error: bpRule.formatMessage };
      }
      const sys = Number.parseInt(match[1], 10);
      const dia = Number.parseInt(match[2], 10);
      if (Number.isNaN(sys) || Number.isNaN(dia)) {
        return { error: bpRule.invalidMessage };
      }
      if (sys <= dia) {
        return { error: bpRule.orderMessage };
      }
      if (
        sys < bpRule.sysMin ||
        sys > bpRule.sysMax ||
        dia < bpRule.diaMin ||
        dia > bpRule.diaMax
      ) {
        return { error: bpRule.plausibleMessage };
      }
      return { error: null };
    }

    default:
      return { error: `Unsupported rule kind: ${rule.kind}` };
  }
}

function runVitalAdvisory(ruleName, value) {
  const str = value == null ? '' : String(value).trim();
  if (str.length === 0) return { advisory: null };

  if (ruleName === 'bloodPressure') {
    const t = VITAL_THRESHOLDS.bloodPressure;
    const match = /^(\d{2,3})\/(\d{2,3})$/.exec(str);
    if (!match) return { advisory: null };
    const sys = Number.parseInt(match[1], 10);
    const dia = Number.parseInt(match[2], 10);
    if (Number.isNaN(sys) || Number.isNaN(dia) || sys <= dia) return { advisory: null };
    if (sys < t.criticalSysLow) {
      return {
        advisory: {
          level: 'critical',
          message: `Systolic BP < ${t.criticalSysLow} mmHg — possible shock`,
        },
      };
    }
    if (sys > t.criticalSysHigh) {
      return {
        advisory: {
          level: 'critical',
          message: `Systolic BP > ${t.criticalSysHigh} mmHg — hypertensive crisis`,
        },
      };
    }
    const sysNormal = sys >= t.normalSysMin && sys <= t.normalSysMax;
    const diaNormal = dia >= t.normalDiaMin && dia <= t.normalDiaMax;
    if (sysNormal && diaNormal) {
      return { advisory: { level: 'normal', message: 'Within normal range' } };
    }
    const parts = [];
    if (!sysNormal) parts.push(`systolic ${t.normalSysMin}–${t.normalSysMax}`);
    if (!diaNormal) parts.push(`diastolic ${t.normalDiaMin}–${t.normalDiaMax}`);
    return {
      advisory: {
        level: 'warning',
        message: `Outside normal range (${parts.join(', ')} mmHg)`,
      },
    };
  }

  const parsed = Number.parseFloat(str);
  if (Number.isNaN(parsed)) return { advisory: null };

  if (ruleName === 'temperature') {
    const t = VITAL_THRESHOLDS.temperature;
    if (parsed < t.hypothermia) {
      return {
        advisory: {
          level: 'hypothermia',
          message: `Hypothermia (< ${t.hypothermia}°F)`,
        },
      };
    }
    if (parsed < t.belowNormal) {
      return {
        advisory: {
          level: 'caution',
          message: `Below normal (${t.belowNormal}–${t.normalMax}°F)`,
        },
      };
    }
    if (parsed <= t.normalMax) {
      return {
        advisory: {
          level: 'normal',
          message: `Normal (${t.belowNormal}–${t.normalMax}°F)`,
        },
      };
    }
    if (parsed <= t.lowGradeFever) {
      return {
        advisory: {
          level: 'caution',
          message: `Low-grade fever (${t.normalMax + 0.1}–${t.lowGradeFever}°F)`,
        },
      };
    }
    if (parsed <= t.fever) {
      return {
        advisory: {
          level: 'warning',
          message: `Fever (${t.lowGradeFever + 0.1}–${t.fever}°F)`,
        },
      };
    }
    if (parsed <= t.highFever) {
      return {
        advisory: {
          level: 'critical',
          message: `High fever (${t.fever + 0.1}–${t.highFever}°F)`,
        },
      };
    }
    return {
      advisory: {
        level: 'critical',
        message: `Hyperpyrexia / Emergency (> ${t.highFever}°F)`,
      },
    };
  }

  if (ruleName === 'pulse') {
    const t = VITAL_THRESHOLDS.pulse;
    if (parsed < t.criticalLow) {
      return {
        advisory: {
          level: 'critical',
          message: `Pulse < ${t.criticalLow} bpm — critically low`,
        },
      };
    }
    if (parsed > t.criticalHigh) {
      return {
        advisory: {
          level: 'critical',
          message: `Pulse > ${t.criticalHigh} bpm — critically high`,
        },
      };
    }
    if (parsed >= t.normalMin && parsed <= t.normalMax) {
      return { advisory: { level: 'normal', message: 'Within normal range' } };
    }
    return {
      advisory: {
        level: 'warning',
        message: `Outside normal range (${t.normalMin}–${t.normalMax} bpm)`,
      },
    };
  }

  if (ruleName === 'spo2') {
    const t = VITAL_THRESHOLDS.spo2;
    if (parsed < t.critical) {
      return {
        advisory: {
          level: 'critical',
          message: `SpO2 < ${t.critical}% — critical`,
        },
      };
    }
    if (parsed < t.emergency) {
      return {
        advisory: {
          level: 'critical',
          message: `SpO2 < ${t.emergency}% — emergency`,
        },
      };
    }
    if (parsed >= t.normalMin && parsed <= t.normalMax) {
      return {
        advisory: {
          level: 'normal',
          message: `Within normal range (${t.normalMin}–${t.normalMax}%)`,
        },
      };
    }
    if (parsed >= t.cautionMin) {
      return {
        advisory: {
          level: 'caution',
          message: `SpO2 ${t.cautionMin}–${t.normalMin - 1}% — caution zone`,
        },
      };
    }
    return {
      advisory: {
        level: 'warning',
        message: `SpO2 ${t.emergency + 1}–${t.emergency}% — concern zone`,
      },
    };
  }

  if (ruleName === 'respiratoryRate') {
    const t = VITAL_THRESHOLDS.respiratoryRate;
    if (parsed < t.criticalLow) {
      return {
        advisory: {
          level: 'critical',
          message: `Resp. rate < ${t.criticalLow} — critically low`,
        },
      };
    }
    if (parsed > t.criticalHigh) {
      return {
        advisory: {
          level: 'critical',
          message: `Resp. rate > ${t.criticalHigh} — critically high`,
        },
      };
    }
    if (parsed >= t.normalMin && parsed <= t.normalMax) {
      return { advisory: { level: 'normal', message: 'Within normal range' } };
    }
    return {
      advisory: {
        level: 'warning',
        message: `Outside normal range (${t.normalMin}–${t.normalMax} breaths/min)`,
      },
    };
  }

  return { advisory: null };
}

function validateFields(checks) {
  const errors = {};
  for (const check of checks || []) {
    const key = check.key || check.rule;
    const result = runRule(check.rule, check.value, check.params || {});
    if (result.error) errors[key] = result.error;
  }
  return { ok: Object.keys(errors).length === 0, errors };
}

module.exports = {
  RULES,
  VITAL_THRESHOLDS,
  runRule,
  runVitalAdvisory,
  validateFields,
};
