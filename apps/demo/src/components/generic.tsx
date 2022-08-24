import styled from 'styled-components'
import { devices, InfoBox, space } from '@glif/react-components'
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
  margin-right: ${space('lg')};
  margin-left: ${space('lg')};
  padding-right: ${space('lg')};
  padding-left: ${space('lg')};

  > * {
    padding: 0;
    margin: 0;
  }

  > p {
    margin-top: ${space('lg')};
    padding-top: ${space('lg')};
    color: var(--gray-light);
  }

  > h3 {
    margin-top: ${space('sm')};
    margin-bottom: ${space('lg')};
    padding-bottom: ${space('lg')};
  }
`
