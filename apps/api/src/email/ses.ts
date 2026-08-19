import { SendEmailCommand, SESv2Client } from '@aws-sdk/client-sesv2';
import type { EmailChannel } from '../trigger/email/send-email';
import type { EmailAttachment } from './resend';

function resolveFromAddress(channel: EmailChannel): string | undefined {
  const fallback = process.env.AWS_SES_FROM_DEFAULT;

  switch (channel) {
    case 'marketing':
      return process.env.AWS_SES_FROM_MARKETING ?? fallback;
    case 'system':
      return process.env.AWS_SES_FROM_SYSTEM ?? fallback;
    case 'trustPortal':
      return process.env.AWS_SES_FROM_TRUST_PORTAL ?? process.env.AWS_SES_FROM_SYSTEM ?? fallback;
    default:
      return fallback;
  }
}

export async function sendEmailViaSes(params: {
  to: string;
  subject: string;
  html: string;
  channel: EmailChannel;
  cc?: string | string[];
  scheduledAt?: string;
  attachments?: EmailAttachment[];
}): Promise<{ id: string }> {
  if (params.scheduledAt) {
    throw new Error('AWS SES fallback does not support scheduled email');
  }
  if (params.attachments?.length) {
    throw new Error('AWS SES fallback does not support email attachments');
  }

  const fromAddress = resolveFromAddress(params.channel);
  if (!fromAddress) {
    throw new Error('Missing AWS_SES_FROM_DEFAULT environment variable');
  }

  const accessKeyId = process.env.APP_AWS_ACCESS_KEY_ID;
  const secretAccessKey = process.env.APP_AWS_SECRET_ACCESS_KEY;
  if (!accessKeyId || !secretAccessKey) {
    throw new Error('Missing AWS email credentials');
  }

  const client = new SESv2Client({
    region: process.env.APP_AWS_REGION ?? process.env.AWS_REGION ?? 'ap-southeast-2',
    credentials: { accessKeyId, secretAccessKey },
  });
  const result = await client.send(
    new SendEmailCommand({
      FromEmailAddress: fromAddress,
      Destination: {
        ToAddresses: [params.to],
        CcAddresses: params.cc ? (Array.isArray(params.cc) ? params.cc : [params.cc]) : undefined,
      },
      Content: {
        Simple: {
          Subject: { Data: params.subject, Charset: 'UTF-8' },
          Body: { Html: { Data: params.html, Charset: 'UTF-8' } },
        },
      },
    }),
  );

  if (!result.MessageId) throw new Error('AWS SES did not return a message ID');
  return { id: result.MessageId };
}
