import { useState } from 'react'
import PropTypes from 'prop-types'
import {
  ButtonV2,
  InputV2,
  ShadowBox as _ShadowBox,
  space
} from '@glif/react-components'
import { FilecoinNumber } from '@glif/filecoin-number'
import styled from 'styled-components'
import { useAccount, useContractWrite, usePrepareContractWrite } from 'wagmi'

import contractDigest from '../../../generated/contractDigest.json'
import { ethers } from 'ethers'
import { useWFILBalance } from '../../utils'
import { useAllowance } from '../../utils/hooks/contracts/useAllowance'

const { WFIL: WFILContract } = contractDigest

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

export function WFIL(props: WFILProps) {
  const { address } = useAccount()
  const [depositAmount, setDepositAmount] = useState(
    new FilecoinNumber('0', 'fil')
  )
  const [allowanceToGrant, setAllowanceToGrant] = useState(
    new FilecoinNumber('0', 'fil')
  )

  const { config: depositConfig, error: depositError } =
    usePrepareContractWrite({
      addressOrName: WFILContract.address,
      contractInterface: WFILContract.abi,
      functionName: 'deposit',
      overrides: {
        value: ethers.utils.parseEther(depositAmount.toFil())
      }
    })

  const { write: deposit } = useContractWrite(depositConfig)

  const { config: allowanceConfig, error: allowanceError } =
    usePrepareContractWrite({
      addressOrName: WFILContract.address,
      contractInterface: WFILContract.abi,
      functionName: 'approve',
      args: [props.poolAddress, allowanceToGrant.toAttoFil()]
    })

  const { write: grantAllowance } = useContractWrite(allowanceConfig)

  const { balance } = useWFILBalance(address)
  const { allowance } = useAllowance(address, props.poolAddress)

  return (
    <>
      <Form
        onSubmit={(e) => {
          e.preventDefault()
          if (!depositError) deposit?.()
        }}
      >
        <ShadowBox>
          <FormContainer>
            <h3>Your balance: {balance.toFil()} WFIL</h3>
            <hr />
            <InputV2.Filecoin
              label='Deposit amount'
              placeholder='0'
              value={depositAmount}
              onChange={setDepositAmount}
            />
            <p>Receive {depositAmount.toFil()} WFIL</p>
          </FormContainer>
        </ShadowBox>
        <ButtonV2 large green type='submit'>
          Deposit
        </ButtonV2>
      </Form>
      <Form
        onSubmit={(e) => {
          e.preventDefault()
          if (!allowanceError) grantAllowance?.()
        }}
      >
        <ShadowBox>
          <FormContainer>
            <h3>Your allowance: {allowance.toFil()} WFIL</h3>
            <hr />
            <InputV2.Filecoin
              label='Allowance amount'
              placeholder='0'
              value={allowanceToGrant}
              onChange={setAllowanceToGrant}
            />
          </FormContainer>
        </ShadowBox>
        <ButtonV2 large green type='submit'>
          Grant allowance
        </ButtonV2>
      </Form>
    </>
  )
}

type WFILProps = {
  poolAddress: string
}

WFIL.propTypes = {
  poolAddress: PropTypes.string.isRequired
}
