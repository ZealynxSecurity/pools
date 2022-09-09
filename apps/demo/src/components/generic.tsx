import styled from 'styled-components'
import { devices, InfoBox } from '@glif/react-components'
import PropTypes from 'prop-types'

export const TableHeader = styled.h3`
  color: var(--purple-medium);
`

export const MetadataContainer = styled(InfoBox)`
  display: flex;
  flex-direction: column;
  flex-wrap: wrap;
  justify-content: space-around;
  width: ${(props) => props.width};

  @media (min-width: ${devices.tablet}) {
    flex-direction: row;
  }
`

MetadataContainer.propTypes = {
  width: PropTypes.string.isRequired
}

const StatContainer = styled.div`
  > * {
    padding: 0;
    margin: 0;
  }
`

export const Stat = ({ title, stat }: StatProps) => (
  <StatContainer>
    <h3>{title}</h3>
    <h2>{stat}</h2>
  </StatContainer>
)

type StatProps = {
  title: string
  stat: string
}

Stat.propTypes = {
  title: PropTypes.string.isRequired,
  stat: PropTypes.string.isRequired
}

export const DataPoint = styled.div`
  display: flex;
  flex-direction: column;
  margin-right: var(--space-l)};
  margin-left: var(--space-l)};
  padding-right: var(--space-l)};
  padding-left: var(--space-l)};

  > * {
    padding: 0;
    margin: 0;
  }

  > p {
    margin-top: var(--space-l);
    padding-top: var(--space-l);
    color: var(--gray-light);
  }

  > h3 {
    margin-top: var(--space-s);
    margin-bottom: var(--space-l);
    padding-bottom: var(--space-l);
  }

  > span {
    display: flex;
    flex-direction: row;
    align-items: center;
    gap: var(--space-s);

    > h2 {
      margin: 0;
      padding: 0;
    }
    > div {
      height: fit-content;
    }
  }
`

export enum DEPOSIT_ELIGIBILITY {
  LOADING,
  NEEDS_FIL,
  NEEDS_WFIL,
  NEEDS_WFIL_ALLOWANCE,
  READY
}
