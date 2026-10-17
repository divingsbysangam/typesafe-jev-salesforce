/**
 * Raised for invalid TypeSafe requests (bad question shapes) and malformed or incomplete
 * responses. HTTP-level failures are not thrown: they are reported on TypeSafeResult so the
 * caller can log them and decide whether to retry.
 */
public class TypeSafeException extends Exception {
}
