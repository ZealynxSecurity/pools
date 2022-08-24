import { TABLE, OneColumnCentered } from '@glif/react-components'
import styled from 'styled-components'
import Layout from '../Layout'
import { PortfolioRow, PortfolioRowColumnTitles } from './table'
import { Opportunities } from './Opportunities'
import { MetadataContainer, TableHeader, Stat } from '../generic'

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
        <TABLE>
          <PortfolioRowColumnTitles />
          <tbody>
            {new Array(3).fill('').map((_, i) => (
              <PortfolioRow key={i} poolID={i} />
            ))}
          </tbody>
        </TABLE>
        <br />
        <Opportunities opportunities={[0, 1, 2]} />
      </PageWrapper>
    </Layout>
  )
}
