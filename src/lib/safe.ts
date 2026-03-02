export const toErrorMessage = (err: unknown): string => {
  if (err instanceof Error) return err.message;
  return String(err);
};

export const asRecord = (value: unknown): Record<string, unknown> => {
  if (value && typeof value === 'object') return value as Record<string, unknown>;
  return {};
};

export const asArray = <T>(value: unknown): T[] => {
  if (Array.isArray(value)) return value as T[];
  return [];
};

