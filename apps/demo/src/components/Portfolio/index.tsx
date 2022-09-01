import { useMemo } from 'react'
import { OneColumnCentered } from '@glif/react-components'
import styled from 'styled-components'
import Layout from '../Layout'
import { PortfolioRow, PortfolioRowColumnTitles } from './table'
import { Opportunities } from './Opportunities'
import { MetadataContainer, TableHeader, Stat } from '../generic'
import contractDigest from '../../../generated/contractDigest.json'
import { useContractRead, useContractReads } from 'wagmi'

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

  const contracts = useMemo(() => {
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

  const { data: poolAddrs } = useContractReads({ contracts })

  return (
    <Layout>
      <PageWrapper>
        <MetadataContainer width='60%'>
          <Stat title='Liquid FIL' stat='100 FIL' />
          <Stat title='Total deposited' stat='69 FIL' />
          <Stat title='Total profit/loss' stat='22 FIL' />
        </MetadataContainer>
        <br />
        <TableHeader>Your Holdings</TableHeader>
        <table>
          <PortfolioRowColumnTitles />
          <tbody>
            {new Array(3).fill('').map((_, i) => (
              <PortfolioRow key={i} poolID={i} />
            ))}
          </tbody>
        </table>
        <br />
        {poolAddrs && poolAddrs.length > 0 ? (
          <Opportunities opportunities={poolAddrs.map((p) => p.toString())} />
        ) : (
          <div>Loading...</div>
        )}
      </PageWrapper>
    </Layout>
  )
}
