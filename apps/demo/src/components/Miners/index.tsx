import { OneColumn } from '@glif/react-components'
import styled from 'styled-components'
import { MetadataContainer, Stat } from '../generic'
import Layout from '../Layout'

const MinerPageWrapper = styled(OneColumn)`
  display: flex;
  flex-direction: column;
  align-items: center;
`

export default function Miners() {
  return (
    <Layout>
      <MinerPageWrapper>
        <MetadataContainer width='40%'>
          <Stat title='Total Miners' stat='259,253' />
          <Stat title='Total Loans' stat='22 Billion FIL' />
        </MetadataContainer>
      </MinerPageWrapper>
    </Layout>
  )
}
