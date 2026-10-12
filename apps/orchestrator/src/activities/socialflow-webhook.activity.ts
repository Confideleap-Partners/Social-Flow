import { Injectable } from '@nestjs/common';
import { WebhooksService } from '@gitroom/nestjs-libraries/database/prisma/webhooks/webhooks.service';
import { IntegrationService } from '@gitroom/nestjs-libraries/database/prisma/integrations/integration.service';
import { OrganizationRepository } from '@gitroom/nestjs-libraries/database/prisma/organizations/organization.repository';

/**
 * Auto-registers the SocialFlow notification webhook the first time a social
 * channel connects (the moment an org starts posting). Idempotent per org:
 * the webhook row is upserted by name and the URL is refreshed on every call.
 * Best-effort — when registration fails (or SOCIALFLOW_WEBHOOK_PUBLIC_URL is
 * unset) notifications degrade to polling, never break posting.
 */
@Injectable()
export class SocialFlowWebhookActivity {
  constructor(
    private _webhookService: WebhooksService,
    private _integrationService: IntegrationService,
    private _organizationRepository: OrganizationRepository
  ) {}

  async registerSocialflowWebhook(orgId: string) {
    if (!process.env.SOCIALFLOW_WEBHOOK_PUBLIC_URL) {
      return;
    }
    try {
      const org = await this._organizationRepository.getOrgById(orgId);
      if (!org) {
        return;
      }
      const webhookUrl = new URL(process.env.SOCIALFLOW_WEBHOOK_PUBLIC_URL);
      webhookUrl.searchParams.set('org', orgId);
      const integrations = await this._integrationService.getIntegrationsList(orgId);
      await this._webhookService.createWebhook(orgId, {
        id: '',
        name: 'socialflow-notifications',
        url: webhookUrl.toString(),
        integrations: integrations.map((i) => ({ id: i.id })),
      });
    } catch (e) {
      return;
    }
  }
}
