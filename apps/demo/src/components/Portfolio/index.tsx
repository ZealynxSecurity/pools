import { useMemo } from 'react'
import { OneColumnCentered } from '@glif/react-components'
import styled from 'styled-components'
import { useAccount, useContractRead, useContractReads } from 'wagmi'

import Layout from '../Layout'
import { Opportunities } from './Opportunities'
import { Holdings } from './Holdings'
import { MetadataContainer, Stat } from '../generic'
import contractDigest from '../../../generated/contractDigest.json'

const { PoolFactory } = contractDigest

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
  const { data: allPoolsLength } = useContractRead({
    addressOrName: PoolFactory.address,
    contractInterface: PoolFactory.abi,
    functionName: 'allPoolsLength'
  })

  const { address } = useAccount()

  const poolContracts = useMemo(() => {
    const pools = []
    if (!!allPoolsLength && Number(allPoolsLength.toString())) {
      for (let i = 0; i < Number(allPoolsLength.toString()); i++) {
        pools.push({
          addressOrName: PoolFactory.address,
          contractInterface: PoolFactory.abi,
          functionName: 'allPools',
          args: [i]
        })
      }
    }
    return pools
  }, [allPoolsLength])

  const { data: poolAddrs } = useContractReads({ contracts: poolContracts })

  return (
    <Layout>
      <PageWrapper>
        <MetadataContainer width='60%'>
          <Stat title='Liquid FIL' stat='100 FIL' />
          <Stat title='Total deposited' stat='69 FIL' />
          <Stat title='Total profit/loss' stat='22 FIL' />
        </MetadataContainer>
        <Holdings
          walletAddress={address}
          poolAddrs={poolAddrs?.map((p) => p.toString())}
        />
        <Opportunities poolAddrs={poolAddrs?.map((p) => p.toString())} />
      </PageWrapper>
    </Layout>
  )
}
