using System;
using System.Security.Cryptography;
using System.Text;

string keyBase64 = "dGVzdC1lbmNyeXB0aW9uLWtleS1vZi0zMi1ieXRlcyE="; // 32 bytes
byte[] _key = Convert.FromBase64String(keyBase64);
string plaintext = "masterkey";

byte[] nonce = new byte[12];
RandomNumberGenerator.Fill(nonce);

byte[] plaintextBytes = Encoding.UTF8.GetBytes(plaintext);
byte[] ciphertext = new byte[plaintextBytes.Length];
byte[] tag = new byte[16];

using var aesgcm = new AesGcm(_key, 16);
aesgcm.Encrypt(nonce, plaintextBytes, ciphertext, tag);

byte[] result = new byte[12 + ciphertext.Length + 16];
Buffer.BlockCopy(nonce, 0, result, 0, 12);
Buffer.BlockCopy(ciphertext, 0, result, 12, ciphertext.Length);
Buffer.BlockCopy(tag, 0, result, 12 + ciphertext.Length, 16);

Console.WriteLine(Convert.ToBase64String(result));
