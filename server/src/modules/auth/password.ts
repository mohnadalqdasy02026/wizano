// تجزئة كلمات المرور — argon2id (D-05).

import { hash, verify, Algorithm } from "@node-rs/argon2";

const hashOptions = {
  algorithm: Algorithm.Argon2id,
  memoryCost: 19456, // ~19MB — موصى به من OWASP
  timeCost: 2,
  parallelism: 1,
};

export async function hashPassword(plain: string): Promise<string> {
  return hash(plain, hashOptions);
}

export async function verifyPassword(
  plain: string,
  hashed: string,
): Promise<boolean> {
  try {
    return await verify(hashed, plain, { algorithm: Algorithm.Argon2id });
  } catch {
    return false;
  }
}
