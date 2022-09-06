import { useMemo } from 'react'
import { makeFriendlyBalance, OneColumnCentered } from '@glif/react-components'
import styled from 'styled-components'
import {
  useAccount,
  useBalance,
  useContractRead,
  useContractReads
} from 'wagmi'

import Layout from '../Layout'
import { Opportunities } from './Opportunities'
import { Holdings } from './Holdings'
import { MetadataContainer, Stat } from '../generic'
import contractDigest from '../../../generated/contractDigest.json'
import { FilecoinNumber } from '@glif/filecoin-number'

const { PoolFactory, SimpleInterestPool } = contractDigest

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
  const { data: balData } = useBalance({ addressOrName: address })
  const balance = useMemo(() => {
    if (balData) {
      const bal = new FilecoinNumber(balData.value.toString(), 'attofil')
      return makeFriendlyBalance(bal, 6, true).toString()
    }
    return ''
  }, [balData])

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

  const totalBalanceContracts = useMemo(() => {
    if (poolAddrs?.length > 0 && !!address) {
      return poolAddrs.map((addr) => {
        return {
          addressOrName: addr.toString(),
          contractInterface: SimpleInterestPool[0].abi,
          functionName: 'balanceOf',
          args: [address]
        }
      })
    }
    return []
  }, [address, poolAddrs])

  const { data: allBalances } = useContractReads({
    contracts: totalBalanceContracts
  })

  const totalDeposited = useMemo(() => {
    if (allBalances) {
      return makeFriendlyBalance(
        allBalances.reduce((total, bal) => {
          return total.plus(new FilecoinNumber(bal.toString(), 'attofil'))
        }, new FilecoinNumber(0, 'fil')),
        6,
        true
      )
    }
    return 0
  }, [allBalances])

  return (
    <Layout>
      <PageWrapper>
        <MetadataContainer width='60%'>
          <Stat title='Liquid FIL' stat={balance} />
          <Stat title='Total deposited' stat={`${totalDeposited} FIL`} />
          <Stat title='Total profit/loss' stat='0 FIL' />
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
