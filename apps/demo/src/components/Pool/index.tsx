import { OneColumn, TwoColumns } from '@glif/react-components'
import styled from 'styled-components'
import { useRouter } from 'next/router'
import { MetadataContainer, Stat } from '../generic'
import Layout from '../Layout'
import { PriceChart } from './PriceChart'
import { Education } from './Education'
import { Transact } from './Transact'

const PoolPageWrapper = styled(OneColumn)`
  display: flex;
  flex-direction: column;
  align-items: center;
`

export default function Pool() {
  const { query } = useRouter()
  return (
    <Layout>
      <PoolPageWrapper>
        <MetadataContainer width='40%'>
          <Stat title='Your holdings' stat='123 P0GLIF' />
          <Stat title='Your earnings' stat='11.258 P0GLIF' />
        </MetadataContainer>
        <PriceChart poolID={Number(query.poolID)} />
      </PoolPageWrapper>
      <TwoColumns>
        <Education />
        <Transact />
      </TwoColumns>
    </Layout>
  )
}
