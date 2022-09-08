import { useState } from 'react'
import styled from 'styled-components'
import {
  FILECOIN_NUMBER_PROPTYPE,
  InputV2,
  ButtonV2,
  ShadowBox as _ShadowBox
} from '@glif/react-components'
import { FilecoinNumber } from '@glif/filecoin-number'
import PropTypes from 'prop-types'
import { Tabs } from '../Tabs'
import { BaseFormProps } from '../types'

export const Form = styled.form`
  margin-left: 10%;
  margin-right: 10%;

  > button {
    width: 100%;
    margin-top: var(--space-m);
  }
`

export const ShadowBox = styled(_ShadowBox)`
  padding: 0;
  padding-bottom: 1.5em;

  > * {
    text-align: center;
  }
`

export const FormContainer = styled.div`
  margin-top: var(--space-l);
  display: flex;
  flex-direction: column;
  justify-content: center;

  > h3 {
    padding-left: var(--space-xl);
    padding-right: var(--space-xl);
  }

  > label {
    width: fit-content;
    margin-left: auto;
    margin-right: auto;
    margin-top: var(--space-l);
    margin-bottom: var(--space-l);
  }
`

export const FormTemplate = (props: BaseFormProps) => {
  const [amount, setAmount] = useState<FilecoinNumber>(
    new FilecoinNumber('0', 'fil')
  )
  return (
    <Form
      onSubmit={async (e) => {
        e.preventDefault()
        await props.onSubmit(amount)
      }}
    >
      <ShadowBox>
        <Tabs tab={props.tab} setTab={props.setTab} />
        <FormContainer>
          <h3>{props.header}</h3>
          <>
            <InputV2.Filecoin
              label={props.inputLabel}
              placeholder='0'
              value={amount}
              onChange={setAmount}
            />
            {props.exchangeRateLabel && (
              <>
                <h3>{props.exchangeRateLabel}</h3>
                {!!amount && (
                  <p>
                    Receive {amount.times(props.exchangeRate).toFil()}{' '}
                    {props.tokenName}
                  </p>
                )}
              </>
            )}
          </>
        </FormContainer>
      </ShadowBox>
      <ButtonV2 large green type='submit'>
        {props.submitBtnText}
      </ButtonV2>
    </Form>
  )
}

FormTemplate.propTypes = {
  address: PropTypes.string.isRequired,
  tab: PropTypes.oneOf(['DEPOSIT', 'WITHDRAW']).isRequired,
  exchangeRate: FILECOIN_NUMBER_PROPTYPE.isRequired,
  poolID: PropTypes.string.isRequired
}
