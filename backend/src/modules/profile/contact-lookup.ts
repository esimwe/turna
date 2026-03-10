function onlyDigits(value: string): string {
  return value.replace(/\D+/g, "");
}

const COUNTRY_DIAL_CODES: Record<string, string> = {
  TR: "90",
  GB: "44",
  US: "1",
  CA: "1",
  DE: "49",
  FR: "33",
  NL: "31",
  BE: "32",
  CH: "41",
  AT: "43",
  ES: "34",
  IT: "39",
  IE: "353",
  SE: "46",
  NO: "47",
  DK: "45",
  FI: "358",
  PL: "48",
  CZ: "420",
  RO: "40",
  BG: "359",
  GR: "30",
  CY: "357",
  UA: "380",
  RU: "7",
  AZ: "994",
  GE: "995",
  AM: "374",
  AE: "971",
  SA: "966",
  QA: "974",
  KW: "965",
  BH: "973",
  OM: "968",
  IQ: "964",
  JO: "962",
  LB: "961",
  EG: "20",
  TN: "216",
  DZ: "213",
  MA: "212",
  PK: "92",
  IN: "91",
  CN: "86",
  JP: "81",
  KR: "82",
  ID: "62",
  MY: "60",
  SG: "65",
  TH: "66",
  VN: "84",
  AU: "61",
  NZ: "64",
  BR: "55",
  AR: "54",
  MX: "52",
  ZA: "27",
  NG: "234",
  KE: "254",
  ET: "251"
};

const UNIQUE_DIAL_CODES = Array.from(new Set(Object.values(COUNTRY_DIAL_CODES))).sort(
  (left, right) => right.length - left.length
);

function resolveCountryDialCode(countryIso: string | null | undefined): string | null {
  const normalized = countryIso?.trim().toUpperCase();
  if (!normalized) return null;
  return COUNTRY_DIAL_CODES[normalized] ?? null;
}

function detectDialCodeFromInternationalDigits(digits: string): string | null {
  for (const dialCode of UNIQUE_DIAL_CODES) {
    if (!digits.startsWith(dialCode)) continue;
    const nationalNumber = digits.substring(dialCode.length);
    if (nationalNumber.length >= 4) {
      return dialCode;
    }
  }

  return null;
}

function normalizeInternationalLookupDigits(
  raw: string | null | undefined,
  options?: {
    defaultCountryIso?: string | null;
  }
): string | null {
  const source = raw?.trim() ?? "";
  if (!source) return null;

  const digits = onlyDigits(source);
  if (digits.length < 7) return null;

  if (source.startsWith("+")) {
    return digits;
  }

  if (digits.startsWith("00") && digits.length > 2) {
    return digits.substring(2);
  }

  if (digits.length > 10) {
    const detectedDialCode = detectDialCodeFromInternationalDigits(digits);
    if (detectedDialCode) {
      return digits;
    }
  }

  const defaultDialCode = resolveCountryDialCode(options?.defaultCountryIso);
  if (!defaultDialCode) {
    return digits;
  }

  const nationalDigits = digits.replace(/^0+/, "");
  if (digits.startsWith("0")) {
    return nationalDigits.length >= 4 ? `${defaultDialCode}${nationalDigits}` : null;
  }

  if (digits.length <= 10) {
    return nationalDigits.length >= 4 ? `${defaultDialCode}${nationalDigits}` : null;
  }

  return digits;
}

export function buildPhoneLookupKeys(
  raw: string | null | undefined,
  options?: {
    defaultCountryIso?: string | null;
  }
): string[] {
  const source = raw?.trim() ?? "";
  if (!source) return [];

  const digits = onlyDigits(source);
  if (digits.length < 7) return [];

  const keys: string[] = [];
  const addKey = (value: string) => {
    const normalized = value.trim();
    if (normalized.length < 7 || keys.includes(normalized)) return;
    keys.push(normalized);
  };

  const canonical = normalizeInternationalLookupDigits(raw, options);
  if (canonical) {
    addKey(canonical);
  }
  addKey(digits);

  const internationalDigits = canonical ?? digits;
  const dialCode =
    detectDialCodeFromInternationalDigits(internationalDigits) ??
    resolveCountryDialCode(options?.defaultCountryIso);

  if (dialCode && internationalDigits.startsWith(dialCode)) {
    const nationalDigits = internationalDigits.substring(dialCode.length).replace(/^0+/, "");
    if (nationalDigits.length >= 4) {
      addKey(nationalDigits);
      addKey(`0${nationalDigits}`);
    }
  }

  return keys;
}

export function buildCanonicalPhoneLookupKey(
  raw: string | null | undefined,
  options?: {
    defaultCountryIso?: string | null;
  }
): string | null {
  return normalizeInternationalLookupDigits(raw, options);
}

export function findLookupDisplayName(
  rawPhone: string | null | undefined,
  labelsByKey: Map<string, string>,
  options?: {
    defaultCountryIso?: string | null;
  }
): string | null {
  for (const key of buildPhoneLookupKeys(rawPhone, options)) {
    const label = labelsByKey.get(key);
    if (label && label.trim()) {
      return label;
    }
  }
  return null;
}
