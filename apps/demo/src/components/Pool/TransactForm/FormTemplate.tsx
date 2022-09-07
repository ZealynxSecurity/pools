import { useState } from 'react'
import {
  FILECOIN_NUMBER_PROPTYPE,
  InputV2,
  ButtonV2
} from '@glif/react-components'
import { FilecoinNumber } from '@glif/filecoin-number'
import PropTypes from 'prop-types'
import { Form, FormContainer, ShadowBox } from '../common'
import { Tabs } from '../Tabs'
import { BaseFormProps } from '../types'

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
