/**
 * Logs that Google Cloud understands (Production plan A7): Cloud Logging
 * reads `severity` and `message` from each JSON line, and Error Reporting
 * groups any entry typed as a ReportedErrorEvent by its stack trace, so
 * crashes show up with counts and alerts without another service.
 */

export const ERROR_EVENT_TYPE = "type.googleapis.com/google.devtools.clouderrorreporting.v1beta1.ReportedErrorEvent";

const SEVERITY: Record<string, string> = {
  trace: "DEBUG",
  debug: "DEBUG",
  info: "INFO",
  warn: "WARNING",
  error: "ERROR",
  fatal: "CRITICAL",
};

/** Pino options (Fastify's logger) for Cloud Run. */
export const cloudLoggerOptions = {
  messageKey: "message",
  formatters: { level: (label: string) => ({ severity: SEVERITY[label] ?? "DEFAULT" }) },
};

/** Fields that make a log entry an Error Reporting event. */
export function errorEvent(service: string, version: string | undefined, stackTrace: string, context: Record<string, unknown> = {}) {
  return {
    "@type": ERROR_EVENT_TYPE,
    serviceContext: { service, version: version || "unknown" },
    stack_trace: stackTrace,
    context,
  };
}
