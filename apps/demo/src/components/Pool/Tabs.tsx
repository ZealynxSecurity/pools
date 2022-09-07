import styled from 'styled-components'
import PropTypes from 'prop-types'
import { TransactTab, TabsProps } from './types'

const Tab = styled.button.attrs(() => ({
  type: 'button'
}))`
  border: none;
  width: 50%;
  text-align: center;
  word-break: break-word;
  padding: 1em;
  cursor: pointer;

  font-size: 1.375em;

  ${(props) =>
    props.selected
      ? `
        background-color: var(--purple-medium);
        color: var(--white);
        border-bottom: 1px solid var(--purple-medium);
      `
      : `
        background-color: var(--white);
        color: var(--purple-medium);
        border-bottom: 1px solid var(--purple-medium);

        &:hover {
          background-color: var(--purple-light);
        }
      `}

  ${(props) => props.firstTab && `border-top-left-radius: 8px;`}

  ${(props) => props.lastTab && `border-top-right-radius: 8px;`}
`

Tab.propTypes = {
  firstTab: PropTypes.bool,
  lastTab: PropTypes.bool,
  selected: PropTypes.bool
}

export const Tabs = ({ tab, setTab }: TabsProps) => {
  return (
    <>
      <Tab
        firstTab
        selected={tab === TransactTab.DEPOSIT}
        onClick={() => {
          setTab(TransactTab.DEPOSIT)
        }}
      >
        Deposit
      </Tab>
      <Tab
        lastTab
        selected={tab === TransactTab.WITHDRAW}
        onClick={() => {
          setTab(TransactTab.WITHDRAW)
        }}
      >
        Withdraw
      </Tab>
    </>
  )
}

Tabs.propTypes = {
  tab: PropTypes.oneOf(['DEPOSIT', 'WITHDRAW']).isRequired,
  setTab: PropTypes.func.isRequired
}
