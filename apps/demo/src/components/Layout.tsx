import {
  Page,
  PageProps,
  PagePropTypes,
  ExplorerIconHeaderFooter,
  NetworkSelector
} from '@glif/react-components'
import { GLIF_DISCORD, PAGE } from '../../constants'

export default function Layout({ children, ...rest }: PageProps) {
  return (
    <Page
      connection={
        <NetworkSelector enableSwitching={false} errorCallback={() => {}} />
      }
      logout={() => {}}
      addressLinks={[
        {
          label: 'Wallet Address',
          address: 't13wmfneijr5pyksi6gtes2v24nw6qh7iuxib7sdy',
          disableLink: false,
          hideCopy: false,
          hideCopyText: true
        },
        {
          label: 'Balance',
          address: '100 FIL',
          disableLink: true,
          hideCopy: true,
          hideCopyText: true
        }
      ]}
      appIcon={<ExplorerIconHeaderFooter />}
      appHeaderLinks={[
        {
          title: 'Portfolio',
          url: PAGE.PORTFOLIO
        },
        {
          title: 'Miners',
          url: PAGE.MINERS
        },
        {
          title: 'Discord',
          url: GLIF_DISCORD
        }
      ]}
      {...rest}
    >
      {children}
    </Page>
  )
}

Layout.propTypes = {
  ...PagePropTypes
}
