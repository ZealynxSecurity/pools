import { useMemo } from 'react'
import { makeFriendlyBalance, OneColumnCentered } from '@glif/react-components'
import { FilecoinNumber } from '@glif/filecoin-number'
import styled from 'styled-components'
import { useAccount, useBalance } from 'wagmi'

import Layout from '../Layout'
import { Opportunities } from './Opportunities'
import { Holdings } from './Holdings'
import { MetadataContainer, Stat } from '../generic'
import { usePools, useAllPoolTokenBalances } from '../../utils'

const PageWrapper = styled(OneColumnCentered)`
  margin-left: 10%;
  margin-right: 10%;

  > h3 {
    margin-top: 0;
    padding-top: 0;
    align-self: flex-start;
  }
`

export default function Portfolio() {
  const { address } = useAccount()
  const { data: balance } = useBalance({
    addressOrName: address,
    formatUnits: 'ether'
  })

  const { pools } = usePools()
  const allPoolBalances = useAllPoolTokenBalances(address)

  const totalDeposited = useMemo(() => {
    if (allPoolBalances) {
      return makeFriendlyBalance(
        Object.keys(allPoolBalances).reduce(
          (total, id) =>
            total.plus(
              new FilecoinNumber(allPoolBalances[id].toString(), 'attofil')
            ),
          new FilecoinNumber(0, 'fil')
        ),
        6,
        true
      )
    }
    return 0
  }, [allPoolBalances])

  return (
    <Layout>
      <PageWrapper>
        <MetadataContainer width='60%'>
          <Stat title='Liquid FIL' stat={balance?.formatted?.toString()} />
          <Stat title='Total deposited' stat={`${totalDeposited} FIL`} />
          <Stat title='Total profit/loss' stat='0 FIL' />
        </MetadataContainer>
        <Holdings walletAddress={address} pools={pools} />
        <Opportunities pools={pools} />
      </PageWrapper>
    </Layout>
  )
}
