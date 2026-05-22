const INVITE_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

export function randomString(alphabet: string, length: number): string {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return [...bytes].map((byte) => alphabet[byte % alphabet.length]).join("");
}

export function generateInviteCode(groups = 4, groupLength = 5): string {
  return Array.from(
    { length: groups },
    () => randomString(INVITE_ALPHABET, groupLength),
  ).join("-");
}

export function generatePassword(length = 24): string {
  return randomString(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
    length,
  );
}
