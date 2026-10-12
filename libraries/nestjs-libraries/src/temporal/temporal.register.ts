import { Global, Injectable, Module, OnModuleInit } from '@nestjs/common';
import { TemporalService } from 'nestjs-temporal-core';
import { Connection } from '@temporalio/client';

@Injectable()
export class TemporalRegister implements OnModuleInit {
  constructor(private _client: TemporalService) {}

  async onModuleInit(): Promise<void> {
    if (process.env.TEMPORAL_TLS === 'true') {
      return;
    }
    const connection = this._client?.client?.getRawClient()
      ?.connection as Connection;

    const { customAttributes } =
      await connection.operatorService.listSearchAttributes({
        namespace: process.env.TEMPORAL_NAMESPACE || 'default',
      });

    const neededAttribute = ['organizationId', 'postId'];
    const missingAttributes = neededAttribute.filter(
      (attr) => !customAttributes[attr]
    );

    if (missingAttributes.length > 0) {
      try {
        await connection.operatorService.addSearchAttributes({
          namespace: process.env.TEMPORAL_NAMESPACE || 'default',
          searchAttributes: missingAttributes.reduce((all, current) => {
            // @ts-ignore
            all[current] = 1;
            return all;
          }, {}),
        });
      } catch (error) {
        // Shared Temporal servers can already be at the per-type attribute
        // limit (Temporal allows max 3 attributes per type). Search
        // attributes are only used for list filtering — boot must not fail
        // because of them; log and continue.
        console.warn(
          'Failed to register Temporal search attributes (non-fatal):',
          error instanceof Error ? error.message : error
        );
      }
    }
  }
}

@Global()
@Module({
  imports: [],
  controllers: [],
  providers: [TemporalRegister],
  get exports() {
    return this.providers;
  },
})
export class TemporalRegisterMissingSearchAttributesModule {}
