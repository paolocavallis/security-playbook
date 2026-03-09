// INTENTIONAL SECURITY VIOLATION — proving CI warns via both stdout and STEP_SUMMARY
// Delete this file after validation

export function handleError(res: any, error: Error) {
  res.status(500).json({
    message: error.message,
    stack: error.stack,
  });
}
