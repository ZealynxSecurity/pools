import {
  ButtonV2,
  FILECOIN_NUMBER_PROPTYPE,
  InputV2,
  ShadowBox as _ShadowBox,
  space
} from '@glif/react-components'
import { FilecoinNumber } from '@glif/filecoin-number'
import PropTypes from 'prop-types'
import styled from 'styled-components'
import { useState } from 'react'
import { useAccount, useContractWrite, usePrepareContractWrite } from 'wagmi'

import contractDigest from '../../../generated/contractDigest.json'
import { usePoolTokenBalance } from '../../utils'

const { SimpleInterestPool } = contractDigest

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

const FormContainer = styled.div`
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

export function Transact(props: TransactProps) {
  const [tab, setTab] = useState<TransactTab>(TransactTab.DEPOSIT)
  const [depositAmount, setDepositAmount] = useState(
    new FilecoinNumber('0', 'fil')
  )
  const [withdrawAmount, setWithdrawAmount] = useState(0)

  const { address } = useAccount()
  const { balance } = usePoolTokenBalance(props.poolID, address)

  const { config: depositConfig, error: depositError } =
    usePrepareContractWrite({
      addressOrName: props.poolAddress,
      contractInterface: SimpleInterestPool[0].abi,
      functionName: 'deposit',
      args: [depositAmount.toAttoFil(), address]
    })

  const { write: deposit } = useContractWrite(depositConfig)

  const { config: withdrawConfig, error: withdrawError } =
    usePrepareContractWrite({
      addressOrName: props.poolAddress,
      contractInterface: SimpleInterestPool[0].abi,
      functionName: 'withdraw',
      args: [
        new FilecoinNumber(withdrawAmount, 'fil').toAttoFil(),
        address,
        address
      ]
    })

  const { write: withdraw } = useContractWrite(withdrawConfig)

  return (
    <Form
      onSubmit={(e) => {
        e.preventDefault()
        if (withdrawAmount > 0 && !withdrawError) withdraw?.()
        else if (depositAmount.isGreaterThan(0) && !depositError) deposit?.()
      }}
    >
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
          <h3>
            Your balance: {balance?.toFil()} P{props.poolID}GLIF
          </h3>
          {tab === TransactTab.DEPOSIT ? (
            <>
              <InputV2.Filecoin
                label='Deposit amount'
                placeholder='0'
                value={depositAmount}
                onChange={setDepositAmount}
              />
              <h3>1 FIL = {props.exchangeRate.toFil()} P0GLIF</h3>
              <p>
                Receive {depositAmount.times(props.exchangeRate).toFil()} P
                {props.poolID}GLIF
              </p>
            </>
          ) : (
            <>
              <InputV2.Number
                label='Withdraw amount'
                placeholder='0'
                value={withdrawAmount}
                onChange={setWithdrawAmount}
              />
              <h3>1 FIL = {props.exchangeRate} P0GLIF</h3>
              <p>
                Receive{' '}
                {new FilecoinNumber(withdrawAmount, 'fil')
                  .times(props.exchangeRate)
                  .toFil()}{' '}
                FIL
              </p>
            </>
          )}
          <hr />
        </FormContainer>
      </ShadowBox>
      <ButtonV2 large green type='submit'>
        {tab}
      </ButtonV2>
    </Form>
  )
}

type TransactProps = {
  poolID: string
  poolAddress: string
  exchangeRate: FilecoinNumber
}

Transact.propTypes = {
  poolID: PropTypes.string,
  poolAddress: PropTypes.string,
  exchangeRate: FILECOIN_NUMBER_PROPTYPE
}

Transact.defaultProps = {
  poolID: '',
  poolAddress: '',
  exchangeRate: new FilecoinNumber('0', 'fil')
}
