function onlyDigits(value) {
    return value.replace(/\D+/g, "");
}
export function normalizeCountryIso(countryIso) {
    const normalized = countryIso.trim().toUpperCase();
    if (!/^[A-Z]{2}$/.test(normalized)) {
        throw new Error("invalid_country_iso");
    }
    return normalized;
}
export function normalizeDialCode(dialCode) {
    const digits = onlyDigits(dialCode);
    if (digits.length < 1 || digits.length > 4) {
        throw new Error("invalid_dial_code");
    }
    return `+${digits}`;
}
export function normalizeNationalNumber(nationalNumber) {
    const digits = onlyDigits(nationalNumber);
    if (digits.length < 4 || digits.length > 15) {
        throw new Error("invalid_national_number");
    }
    const withoutTrunkPrefix = digits.replace(/^0+/, "");
    if (withoutTrunkPrefix.length < 4 || withoutTrunkPrefix.length > 15) {
        throw new Error("invalid_national_number");
    }
    return withoutTrunkPrefix;
}
export function formatE164Phone(input) {
    const dialCode = normalizeDialCode(input.dialCode);
    const nationalNumber = normalizeNationalNumber(input.nationalNumber);
    const phone = `${dialCode}${nationalNumber}`;
    if (!/^\+\d{8,15}$/.test(phone)) {
        throw new Error("invalid_phone");
    }
    return phone;
}
export function normalizeE164Phone(phone) {
    const trimmed = phone.trim();
    const hasPlus = trimmed.startsWith("+");
    const digits = onlyDigits(trimmed);
    const normalized = `${hasPlus ? "+" : "+"}${digits}`;
    if (!/^\+\d{8,15}$/.test(normalized)) {
        throw new Error("invalid_phone");
    }
    return normalized;
}
export function buildDefaultDisplayName(phone) {
    const digits = onlyDigits(phone);
    return `user_${digits.slice(-6) || digits}`;
}
