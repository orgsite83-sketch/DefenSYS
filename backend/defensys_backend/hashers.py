from django.contrib.auth.hashers import PBKDF2PasswordHasher


class OptimizedPBKDF2PasswordHasher(PBKDF2PasswordHasher):
    """
    PBKDF2 hasher configured with OWASP-recommended iteration count (390,000).
    Django 6's default of 1,200,000 iterations takes >1.0s per hash on typical
    CPUs, causing massive delays during user batch imports.
    """
    iterations = 390000
