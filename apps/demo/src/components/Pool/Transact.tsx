import {
  ButtonV2,
  InputV2,
  ShadowBox as _ShadowBox,
  space
} from '@glif/react-components'
import PropTypes from 'prop-types'
import styled from 'styled-components'
import { useState } from 'react'

const Form = styled.form`
  margin-left: 10%;
  margin-right: 10%;

  > button {
    width: 100%;
    margin-top: ${space()};
  }
`

const ShadowBox = styled(_ShadowBox)`
  padding: 0;
  padding-bottom: 1.5em;

  > * {
    text-align: center;
  }
`

const FormContainer = styled.form`
  margin-top: ${space('lg')};
  display: flex;
  flex-direction: column;
  justify-content: center;

  > label {
    width: fit-content;
    margin-left: auto;
    margin-right: auto;
    margin-top: ${space('lg')};
    margin-bottom: ${space('lg')};
  }
`

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

Tab.propTYpes = {
  firstTab: PropTypes.bool,
  lastTab: PropTypes.bool,
  selected: PropTypes.bool
}

enum TransactTab {
  DEPOSIT = 'DEPOSIT',
  WITHDRAW = 'WITHDRAW'
}

export function Transact() {
  const [tab, setTab] = useState<TransactTab>(TransactTab.DEPOSIT)

  return (
    <Form>
      <ShadowBox>
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
        <FormContainer>
          <InputV2.Number label='Deposit amount' unit='FIL' placeholder='0' />
          <h3>1 FIL = 0.99 P0GLIF</h3>
          <InputV2.Number label='Receive' unit='P0GLIF' placeholder='0' />
          <hr />
        </FormContainer>
      </ShadowBox>
      <ButtonV2 large green>
        {tab}
      </ButtonV2>
    </Form>
  )
}
