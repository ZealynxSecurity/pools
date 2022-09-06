import { OneColumn, TwoColumns } from '@glif/react-components'
import { FilecoinNumber } from '@glif/filecoin-number'
import styled from 'styled-components'
import { useRouter } from 'next/router'
import { useAccount, useContractRead, useContractReads } from 'wagmi'
import { MetadataContainer, Stat } from '../generic'
import Layout from '../Layout'
import { PriceChart } from './PriceChart'
import { Education } from './Education'
import { Transact } from './Transact'
import contractDigest from '../../../generated/contractDigest.json'
import { WFIL } from './WFIL'

const { PoolFactory, SimpleInterestPool } = contractDigest

const PoolPageWrapper = styled(OneColumn)`
  display: flex;
  flex-direction: column;
  align-items: center;
`

export default function Pool() {
  const { query } = useRouter()
  const { address } = useAccount()

  const { data: poolAddr } = useContractRead({
    addressOrName: PoolFactory.address,
    contractInterface: PoolFactory.abi,
    functionName: 'allPools',
    args: [Number(query.id)]
  })

  const contracts = [
    {
      addressOrName: poolAddr?.toString(),
      contractInterface: SimpleInterestPool[0].abi,
      functionName: 'balanceOf',
      args: [address]
    },
    {
      addressOrName: poolAddr?.toString(),
      contractInterface: SimpleInterestPool[0].abi,
      functionName: 'previewDeposit',
      args: [1]
    }
  ]

  const { data } = useContractReads({ contracts })

  return (
    <Layout>
      <PoolPageWrapper>
        {data && (
          <MetadataContainer width='40%'>
            <Stat
              title='Your holdings'
              stat={`${new FilecoinNumber(
                data[0]?.toString(),
                'attofil'
              ).toFil()} P${query.id}GLIF`}
            />
            <Stat title='Your earnings' stat='0 P0GLIF' />
          </MetadataContainer>
        )}
        <PriceChart poolID={Number(query.id)} />
      </PoolPageWrapper>
      <TwoColumns>
        <Education />
        <div>
          <WFIL poolAddress={poolAddr?.toString() || ''} />
          <Transact
            poolID={query.id as string}
            poolAddress={poolAddr?.toString() || ''}
            exchangeRate={data?.[1]?.toString()}
          />
        </div>
      </TwoColumns>
    </Layout>
  )
}
