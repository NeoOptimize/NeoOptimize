const crypto = require('crypto');

/**
 * Zero-Knowledge Architecture (E2EE) Scaffolding
 * Encrypts payload completely so the server cannot read telemetry or commands.
 * Server just acts as a blind router between Dashboard and Agent.
 */
class EndToEndEncryption {
  constructor() {
    this.algorithm = 'aes-256-gcm';
  }

  // Generate an ECDH KeyPair for the server (In practice, only Agent and Dashboard have keys)
  generateKeyPair() {
    return crypto.generateKeyPairSync('x25519');
  }

  // Encrypt payload with a shared secret
  encrypt(payload, sharedSecret) {
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv(this.algorithm, sharedSecret, iv);
    
    let encrypted = cipher.update(JSON.stringify(payload), 'utf8', 'hex');
    encrypted += cipher.final('hex');
    const authTag = cipher.getAuthTag().toString('hex');
    
    return {
      iv: iv.toString('hex'),
      encryptedData: encrypted,
      authTag: authTag
    };
  }

  // Decrypt payload with a shared secret
  decrypt(encryptedObj, sharedSecret) {
    const decipher = crypto.createDecipheriv(
      this.algorithm, 
      sharedSecret, 
      Buffer.from(encryptedObj.iv, 'hex')
    );
    decipher.setAuthTag(Buffer.from(encryptedObj.authTag, 'hex'));
    
    let decrypted = decipher.update(encryptedObj.encryptedData, 'hex', 'utf8');
    decrypted += decipher.final('utf8');
    return JSON.parse(decrypted);
  }
}

module.exports = new EndToEndEncryption();
