export default {
  '@context': 'http://schema.org/',
  '@type': 'WebApplication',
  name: 'Glif Staker',
  description: 'Put your $FIL to work.',
  url: 'https://staker.glif.io',
  knowsAbout: [
    {
      '@type': 'SoftwareApplication',
      name: 'Filecoin',
      url: 'https://filecoin.io',
      applicationCategory: 'Blockchain network',
      operatingSystem: 'All'
    }
  ],
  parentOrganization: {
    '@type': 'Organization',
    name: 'Glif',
    description: '.',
    url: 'https://apps.glif.io'
  }
}
