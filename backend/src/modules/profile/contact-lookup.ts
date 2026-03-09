function onlyDigits(value: string): string {
  return value.replace(/\D+/g, "");
}

export function buildPhoneLookupKeys(raw: string | null | undefined): string[] {
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

  addKey(digits);
  if (digits.startsWith("00") && digits.length > 2) {
    addKey(digits.substring(2));
    addKey(`0${digits.substring(2)}`);
  }
  if (digits.startsWith("90") && digits.length == 12) {
    addKey(digits.substring(2));
    addKey(`0${digits.substring(2)}`);
  }
  if (digits.startsWith("1") && digits.length == 11) {
    addKey(digits.substring(1));
  }
  if (digits.length > 10) {
    addKey(digits.substring(digits.length - 10));
  }

  return keys;
}

export function findLookupDisplayName(
  rawPhone: string | null | undefined,
  labelsByKey: Map<string, string>
): string | null {
  for (const key of buildPhoneLookupKeys(rawPhone)) {
    const label = labelsByKey.get(key);
    if (label && label.trim()) {
      return label;
    }
  }
  return null;
}
