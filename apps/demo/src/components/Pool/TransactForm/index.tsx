import { Dispatch, SetStateAction } from 'react'
import { FilecoinNumber } from '@glif/filecoin-number'
import { FILECOIN_NUMBER_PROPTYPE } from '@glif/react-components'
import PropTypes from 'prop-types'

import { TransactTab } from '../types'
import { DEPOSIT_ELIGIBILITY } from '../../generic'
import { FormTemplate } from './FormTemplate'
import { SimpleInterestPool, WFIL } from '../../../../typechain'

export const TransactForm = (props: TransactFormProps) => {
  if (props.tab === TransactTab.DEPOSIT) {
    switch (props.depositEligibility) {
      case DEPOSIT_ELIGIBILITY.LOADING:
        return <>Loading...</>
      case DEPOSIT_ELIGIBILITY.NEEDS_FIL:
        return <>Need FIL</>
      case DEPOSIT_ELIGIBILITY.NEEDS_WFIL:
        return (
          <FormTemplate
            header='In order to deposit $FIL into this pool, you must first convert $FIL into $WFIL.'
            inputLabel='Deposit Amount'
            exchangeRateLabel='1 FIL = 1 WFIL'
            exchangeRate={props.exchangeRate}
            submitBtnText='GET WFIL'
            onSubmit={async (amount) => {
              await props.wFILContract.deposit({
                value: amount.toAttoFil()
              })
            }}
            tab={props.tab}
            setTab={props.setTab}
            poolID={props.poolID}
            tokenName='WFIL'
          />
        )
      case DEPOSIT_ELIGIBILITY.NEEDS_WFIL_ALLOWANCE:
        return (
          <FormTemplate
            header='In order to deposit WFIL into this pool, you must grant the pool an allowance to spend the amount you wish to deposit.'
            inputLabel='Allowance Amount'
            submitBtnText='GRANT ALLOWANCE'
            onSubmit={async (amount) => {
              if (amount.isGreaterThan(0)) {
                await props.wFILContract.approve(
                  props.poolAddress,
                  amount.toAttoFil()
                )
              }
            }}
            tab={props.tab}
            setTab={props.setTab}
            poolID={props.poolID}
            tokenName={`P
        ${props.poolID}GLIF`}
          />
        )
      case DEPOSIT_ELIGIBILITY.READY:
        return (
          <FormTemplate
            header={`
            Available to deposit: ${props.allowance.toFil()} WFIL`}
            inputLabel='Deposit Amount'
            exchangeRateLabel={`1 WFIL = ${props.exchangeRate.toFil()} P${
              props.poolID
            }GLIF`}
            exchangeRate={props.exchangeRate}
            submitBtnText='DEPOSIT'
            onSubmit={async (amount) => {
              if (amount.isGreaterThan(0)) {
                await props.simpleInterestContract.deposit(
                  amount.toAttoFil(),
                  props.address
                )
              }
            }}
            tab={props.tab}
            setTab={props.setTab}
            poolID={props.poolID}
            tokenName={`P
            ${props.poolID}GLIF`}
          />
        )
      default:
        return <>Error...</>
    }
  }

  return (
    <FormTemplate
      header={`Your balance: ${props.poolTokenBalance.toFil()} P${
        props.poolID
      }GLIF`}
      inputLabel='Withdraw Amount'
      exchangeRateLabel={`1 FIL = ${props.exchangeRate.toFil()} P${
        props.poolID
      }GLIF`}
      exchangeRate={new FilecoinNumber('1', 'fil')}
      submitBtnText='WITHDRAW'
      onSubmit={async (amount) => {
        if (amount.isGreaterThan(0)) {
          await props.simpleInterestContract.withdraw(
            amount.toAttoFil(),
            props.address,
            props.address
          )
        }
      }}
      tab={props.tab}
      setTab={props.setTab}
      poolID={props.poolID}
      tokenName='FIL'
    />
  )
}

type TransactFormProps = {
  address: string
  poolAddress: string
  tab: TransactTab
  setTab: Dispatch<SetStateAction<TransactTab>>
  poolID: string
  poolTokenBalance: FilecoinNumber
  allowance: FilecoinNumber
  wFILBalance: FilecoinNumber
  exchangeRate: FilecoinNumber
  simpleInterestContract: SimpleInterestPool
  wFILContract: WFIL
  depositEligibility: DEPOSIT_ELIGIBILITY
}

TransactForm.propTypes = {
  tab: PropTypes.oneOf(['DEPOSIT', 'WITHDRAW']),
  depositEligibility: PropTypes.number.isRequired,
  exchangeRate: FILECOIN_NUMBER_PROPTYPE,
  poolTokenBalance: FILECOIN_NUMBER_PROPTYPE,
  poolID: PropTypes.string,
  contract: PropTypes.object
}

TransactForm.defaultProps = {
  poolID: '',
  contract: null,
  exchangeRate: new FilecoinNumber('0', 'fil'),
  poolTokenBalance: new FilecoinNumber('0', 'fil')
}
