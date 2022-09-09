import { FILECOIN_NUMBER_PROPTYPE } from '@glif/react-components'
import { FilecoinNumber } from '@glif/filecoin-number'
import PropTypes from 'prop-types'
import { useEffect, useMemo, useState } from 'react'
import { useAccount, useBalance, useSigner } from 'wagmi'

import { useAllowance, usePoolTokenBalance, useWFILBalance } from '../../utils'
import { TransactTab } from './types'
import { DEPOSIT_ELIGIBILITY } from '../generic'
import { TransactForm } from './TransactForm'
import {
  SimpleInterestPool,
  SimpleInterestPool__factory,
  WFIL,
  WFIL__factory
} from '../../../typechain'
import contractDigest from '../../../generated/contractDigest.json'

export function Transact(props: TransactProps) {
  const [tab, setTab] = useState<TransactTab>(TransactTab.DEPOSIT)
  const [depositEligibility, setDepositEligibility] =
    useState<DEPOSIT_ELIGIBILITY>(DEPOSIT_ELIGIBILITY.LOADING)
  const { address } = useAccount()
  const {
    data: filBalance,
    isLoading: filBalLoading,
    error: filBalErr
  } = useBalance({
    addressOrName: address,
    formatUnits: 'ether'
  })
  const { balance: poolTokenBalance } = usePoolTokenBalance(
    props.poolID,
    address
  )
  const { data: signer } = useSigner()

  const { simpleInterestContract, wFILContract } = useMemo<{
    simpleInterestContract: SimpleInterestPool
    wFILContract: WFIL
  }>(() => {
    if (!props.poolAddress || !signer)
      return { simpleInterestContract: null, wFILContract: null }
    const simpleInterestContract = SimpleInterestPool__factory.connect(
      props.poolAddress,
      signer
    )
    const wFILContract = WFIL__factory.connect(
      contractDigest.WFIL.address,
      signer
    )
    return { simpleInterestContract, wFILContract }
  }, [props.poolAddress, signer])

  const {
    balance: wFILBal,
    loading: wFILBalLoading,
    error: wFILBalErr
  } = useWFILBalance(address)
  const {
    allowance: wFILAllowance,
    loading: allowanceLoading,
    error: allowanceErr
  } = useAllowance(address, props.poolAddress)

  // based on contract data, set the UI state
  useEffect(() => {
    if (
      !!address &&
      !allowanceErr &&
      !allowanceLoading &&
      !wFILBalLoading &&
      !wFILBalErr &&
      !filBalErr &&
      !filBalLoading
    ) {
      if (
        wFILBal.isEqualTo(0) &&
        depositEligibility < DEPOSIT_ELIGIBILITY.NEEDS_WFIL
      ) {
        // if the user has no WFIL but has FIL, they need to deposit to get WFIL
        if (filBalance.value.gt(0)) {
          setDepositEligibility(DEPOSIT_ELIGIBILITY.NEEDS_WFIL)
        } else {
          // only make this check if the user also doesn't have WFIL
          setDepositEligibility(DEPOSIT_ELIGIBILITY.NEEDS_FIL)
        }
      } else if (
        wFILBal.isGreaterThan(0) &&
        wFILAllowance.isEqualTo(0) &&
        depositEligibility < DEPOSIT_ELIGIBILITY.NEEDS_WFIL_ALLOWANCE
      ) {
        setDepositEligibility(DEPOSIT_ELIGIBILITY.NEEDS_WFIL_ALLOWANCE)
      } else if (
        wFILAllowance.isGreaterThan(0) &&
        depositEligibility < DEPOSIT_ELIGIBILITY.READY
      ) {
        setDepositEligibility(DEPOSIT_ELIGIBILITY.READY)
      }
    }
  }, [
    wFILBal,
    wFILAllowance,
    wFILBalLoading,
    wFILBalErr,
    allowanceLoading,
    allowanceErr,
    depositEligibility,
    filBalance,
    filBalLoading,
    filBalErr,
    address
  ])

  return (
    <TransactForm
      address={address}
      poolAddress={props.poolAddress}
      wFILBalance={wFILBal}
      allowance={wFILAllowance}
      tab={tab}
      depositEligibility={depositEligibility}
      setTab={setTab}
      poolID={props.poolID}
      poolTokenBalance={poolTokenBalance}
      exchangeRate={props.exchangeRate}
      simpleInterestContract={simpleInterestContract}
      wFILContract={wFILContract}
    />
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
