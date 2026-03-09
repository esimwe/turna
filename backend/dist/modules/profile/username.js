const USERNAME_PATTERN = /^[a-z][a-z0-9._]{2,23}$/;
export function normalizeUsername(raw) {
    return raw.trim().replace(/^@+/, "").toLowerCase();
}
export function isValidUsername(raw) {
    return USERNAME_PATTERN.test(normalizeUsername(raw));
}
export function usernamePattern() {
    return USERNAME_PATTERN;
}
