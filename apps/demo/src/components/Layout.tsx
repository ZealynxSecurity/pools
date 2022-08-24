import {
  Page,
  PageProps,
  PagePropTypes,
  ExplorerIconHeaderFooter,
  NetworkConnection
} from '@glif/react-components'
import { GLIF_DISCORD, PAGE } from '../../constants'

export default function Layout({ children, ...rest }: PageProps) {
  return (
    <Page
      connection={
        <NetworkConnection
          lotusApiAddr={process.env.NEXT_PUBLIC_LOTUS_NODE_JSONRPC}
          apiKey={process.env.NEXT_PUBLIC_NODE_STATUS_API_KEY}
          statusApiAddr={process.env.NEXT_PUBLIC_NODE_STATUS_API_ADDRESS}
          errorCallback={() => {}}
        />
      }
      logout={() => {}}
      addressLinks={[
        {
          label: 'Wallet Address',
          address: 't13wmfneijr5pyksi6gtes2v24nw6qh7iuxib7sdy',
          disableLink: false,
          stopPropagation: true,
          hideCopy: false,
          hideCopyText: true
        },
        {
          label: 'Balance',
          address: '100 FIL',
          disableLink: true,
          stopPropagation: true,
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
