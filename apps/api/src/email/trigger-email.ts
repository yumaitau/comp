import { render } from '@react-email/render';
import { tasks } from '@trigger.dev/sdk';
import type { ReactElement } from 'react';
import type { EmailChannel, sendEmailTask } from '../trigger/email/send-email';
import { sendEmail, type EmailAttachment } from './resend';
import { sendEmailViaSes } from './ses';

type TriggerEmailFlags = {
  marketing?: boolean;
  system?: boolean;
  trustPortal?: boolean;
};

function resolveChannel(flags: TriggerEmailFlags): EmailChannel {
  if (flags.trustPortal) return 'trustPortal';
  if (flags.marketing) return 'marketing';
  if (flags.system) return 'system';
  return 'default';
}

export async function triggerEmail(params: {
  to: string;
  subject: string;
  react: ReactElement;
  marketing?: boolean;
  system?: boolean;
  trustPortal?: boolean;
  cc?: string | string[];
  scheduledAt?: string;
  attachments?: EmailAttachment[];
}): Promise<{ id: string }> {
  try {
    const html = await render(params.react);

    const channel = resolveChannel(params);

    if (!process.env.TRIGGER_SECRET_KEY) {
      if (process.env.RESEND_API_KEY) {
        const result = await sendEmail({
          to: params.to,
          subject: params.subject,
          react: params.react,
          marketing: params.marketing,
          system: params.system || params.trustPortal,
          cc: params.cc,
          scheduledAt: params.scheduledAt,
          attachments: params.attachments,
        });

        if (!result.id) throw new Error('Resend did not return a message ID');
        return { id: result.id };
      }

      return sendEmailViaSes({
        to: params.to,
        subject: params.subject,
        html,
        channel,
        cc: params.cc,
        scheduledAt: params.scheduledAt,
        attachments: params.attachments,
      });
    }

    const handle = await tasks.trigger<typeof sendEmailTask>('send-email', {
      to: params.to,
      subject: params.subject,
      html,
      channel,
      cc: params.cc,
      scheduledAt: params.scheduledAt,
      attachments: params.attachments?.map((att) => ({
        filename: att.filename,
        content:
          typeof att.content === 'string'
            ? att.content
            : att.content.toString('base64'),
        contentType: att.contentType,
      })),
    });

    return { id: handle.id };
  } catch (error) {
    console.error('[triggerEmail] Failed to trigger email task', {
      to: params.to,
      subject: params.subject,
      error: error instanceof Error ? error.message : String(error),
    });
    throw error;
  }
}
