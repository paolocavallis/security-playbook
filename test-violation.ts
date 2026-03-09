// INTENTIONAL SECURITY VIOLATION — proving the CI warning path works
// This file should trigger the env-check "error.message leakage" detection
// Delete this file after validation

export function handleError(res: any, error: Error) {
  res.status(500).json({
    message: error.message,
    stack: error.stack,
  });
}
