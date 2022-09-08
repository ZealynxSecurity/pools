import { OneColumn } from '@glif/react-components'
import styled from 'styled-components'
import { MetadataContainer, Stat } from '../generic'
import Layout from '../Layout'
import contractDigest from '../../../generated/contractDigest.json'
import { useContractRead } from 'wagmi'
import { Repay } from './Repay'
const { LoanAgentFactory } = contractDigest

const MinerPageWrapper = styled(OneColumn)`
  display: flex;
  flex-direction: column;
  align-items: center;
`

export default function Borrow() {
  const { data } = useContractRead({
    addressOrName: LoanAgentFactory.address,
    contractInterface: LoanAgentFactory.abi,
    functionName: 'count'
  })

  return (
    <Layout>
      <MinerPageWrapper>
        <MetadataContainer width='40%'>
          <Stat title='Total Miners' stat={data?.toString()} />
          <Stat title='Total Loans' stat='22 Billion FIL' />
        </MetadataContainer>
        <Repay />
      </MinerPageWrapper>
    </Layout>
  )
}
