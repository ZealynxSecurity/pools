import {
  makeFriendlyBalance,
  OneColumn,
  TwoColumns
} from '@glif/react-components'
import styled from 'styled-components'
import { useRouter } from 'next/router'
import { useAccount } from 'wagmi'

import { MetadataContainer, Stat } from '../generic'
import Layout from '../Layout'
import { PriceChart } from './PriceChart'
import { Education } from './Education'
import { Transact } from './Transact'
import { usePoolTokenBalance, usePool } from '../../utils'

const PoolPageWrapper = styled(OneColumn)`
  display: flex;
  flex-direction: column;
  align-items: center;
`

export default function Pool() {
  const { query } = useRouter()
  const { address } = useAccount()

  const { balance } = usePoolTokenBalance(query.id as string, address)
  const pool = usePool(query.id as string)

  return (
    <Layout>
      <PoolPageWrapper>
        {!!balance && (
          <MetadataContainer width='40%'>
            <Stat
              title='Your holdings'
              stat={makeFriendlyBalance(balance, 6, true).toString()}
            />
            <Stat title='Your earnings' stat='0 P0GLIF' />
          </MetadataContainer>
        )}
        <PriceChart poolID={Number(query.id)} />
      </PoolPageWrapper>
      <TwoColumns>
        <Education
          poolID={pool.id}
          name={pool.name}
          interestRate={pool.interestRate}
          totalAssets={pool.totalAssets}
        />
        <Transact
          poolID={pool?.id || ''}
          poolAddress={pool?.address || ''}
          exchangeRate={pool?.exchangeRate}
        />
      </TwoColumns>
    </Layout>
  )
}
