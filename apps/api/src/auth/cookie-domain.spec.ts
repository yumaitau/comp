import { resolveAuthCookieDomain } from './cookie-domain';

describe('resolveAuthCookieDomain', () => {
  it('uses an explicitly configured cookie domain', () => {
    expect(
      resolveAuthCookieDomain(
        'https://trycomp-api.yumait.au',
        '.yumait.au',
      ),
    ).toBe('.yumait.au');
  });

  it('keeps existing TryCompAI production domain detection', () => {
    expect(resolveAuthCookieDomain('https://api.trycomp.ai')).toBe(
      '.trycomp.ai',
    );
  });

  it('keeps existing TryCompAI staging domain detection', () => {
    expect(resolveAuthCookieDomain('https://api.staging.trycomp.ai')).toBe(
      '.staging.trycomp.ai',
    );
  });

  it('leaves unrelated domains host-only without explicit configuration', () => {
    expect(resolveAuthCookieDomain('https://api.example.com')).toBeUndefined();
  });
});
