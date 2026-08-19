export function resolveAuthCookieDomain(
  baseUrl: string,
  configuredDomain?: string,
): string | undefined {
  const explicitDomain = configuredDomain?.trim();
  if (explicitDomain) return explicitDomain;

  if (baseUrl.includes('staging.trycomp.ai')) {
    return '.staging.trycomp.ai';
  }
  if (baseUrl.includes('trycomp.ai')) {
    return '.trycomp.ai';
  }
  return undefined;
}
