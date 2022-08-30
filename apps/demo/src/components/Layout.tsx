import {
  Page,
  PageProps,
  PagePropTypes,
  ExplorerIconHeaderFooter,
  ButtonV2,
  makeFriendlyBalance
} from '@glif/react-components'
import { FilecoinNumber } from '@glif/filecoin-number'
import { useMemo } from 'react'
import { useAccount, useBalance, useConnect } from 'wagmi'
import { GLIF_DISCORD, PAGE } from '../../constants'

export default function Layout({ children, ...rest }: PageProps) {
  const { address, isConnected } = useAccount()
  const { data: bal } = useBalance({ addressOrName: address })
  const { connect, connectors } = useConnect()

  const addressLinks = useMemo(() => {
    const links = []
    if (isConnected && address) {
      links.push({
        label: 'Wallet Address',
        address,
        disableLink: true,
        hideCopy: false,
        hideCopyText: true
      })
    }

    if (bal) {
      const friendlyBal = new FilecoinNumber(bal.value.toString(), 'attofil')
      links.push({
        label: 'Balance',
        address: `${makeFriendlyBalance(friendlyBal, 6, true)} FIL`,
        disableLink: true,
        hideCopy: true,
        hideCopyText: true
      })
    }

    return links
  }, [address, bal, isConnected])

  return (
    <Page
      // TODO: add connection loading indication https://wagmi.sh/examples/connect-wallet
      // TODO: auto switch network to FVM
      connection={
        !address &&
        !isConnected && (
          // for now we only allow connect with MetaMask
          <ButtonV2 green onClick={() => connect({ connector: connectors[0] })}>
            Connect wallet
          </ButtonV2>
        )
      }
      logout={() => {}}
      addressLinks={addressLinks}
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
