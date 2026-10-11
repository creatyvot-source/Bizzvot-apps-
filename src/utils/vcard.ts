import { DigitalCard } from '../types';

/**
 * Generates an RFC 2426 compliant vCard (.vcf) string and triggers a browser download.
 */
export function downloadVCard(card: DigitalCard): void {
  const nameParts = card.fullName.trim().split(' ');
  const lastName = nameParts.length > 1 ? nameParts[nameParts.length - 1] : '';
  const firstName = nameParts.length > 1 ? nameParts.slice(0, -1).join(' ') : card.fullName;

  const vcardLines = [
    'BEGIN:VCARD',
    'VERSION:3.0',
    `N:${lastName};${firstName};;;`,
    `FN:${card.fullName}`,
    `ORG:${card.companyName}`,
    `TITLE:${card.jobTitle}`,
    `EMAIL;type=INTERNET;type=WORK:${card.email}`,
    `TEL;type=WORK,VOICE:${card.phone}`,
    `ADR;type=WORK:;;${card.location};;;;`,
    `NOTE:${card.bio.replace(/\n/g, '\\n')}`,
    `URL:${window.location.origin}/card/${card.slug}`,
    'REV:' + new Date().toISOString(),
    'END:VCARD',
  ];

  const vcardData = vcardLines.join('\r\n');
  const blob = new Blob([vcardData], { type: 'text/vcard;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  
  const link = document.createElement('a');
  link.href = url;
  link.setAttribute('download', `${card.slug || 'contact'}.vcf`);
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}
