import { LinkedinProvider } from './libraries/nestjs-libraries/src/integrations/social/linkedin.provider';

process.on('uncaughtException', (e) => {
  console.log('UNCAUGHT EXCEPTION:', e?.constructor?.name, e?.message);
});
process.on('unhandledRejection', (e: any) => {
  console.log('UNHANDLED REJECTION:', e?.constructor?.name, e?.message);
});

async function main() {
  const provider = new LinkedinProvider();
  const integration: any = { id: 'x', token: 'fake-token', providerIdentifier: 'linkedin' };
  try {
    const result = await provider.getComments('fake-token', 'urn:li:share:9999999999999', integration);
    console.log('RESULT:', JSON.stringify(result).slice(0, 200));
  } catch (err: any) {
    console.log('THROWN:', err?.constructor?.name, '| isError:', err instanceof Error, '| message:', JSON.stringify(err?.message)?.slice(0, 120));
    try {
      console.log('JSON of err:', JSON.stringify(err)?.slice(0, 200));
    } catch (e: any) {
      console.log('JSON.stringify(err) CRASHED:', e?.message);
    }
    // Simulate the controller's catch + Nest HttpException serialization
    try {
      const payload = JSON.stringify({ msg: err?.message || 'Failed to fetch comments' });
      console.log('HttpException payload ok:', payload.slice(0, 150));
    } catch (e: any) {
      console.log('HttpException payload CRASHED:', e?.message);
    }
  }
  console.log('process still alive, exiting cleanly');
  process.exit(0);
}

main();
