package com.example.simplecalculator

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.example.simplecalculator.databinding.ActivityMainBinding
import java.math.BigDecimal
import java.math.MathContext
import java.math.RoundingMode

private enum class Operator(val symbol: String) {
    ADD("+"), SUBTRACT("−"), MULTIPLY("×"), DIVIDE("÷")
}

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding

    private var currentInput: String = "0"
    private var storedValue: BigDecimal? = null
    private var pendingOperator: Operator? = null
    private var expressionText: String = ""
    private var startFreshInput: Boolean = true
    private var lastResultShown: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        setupNumberButtons()
        setupOperatorButtons()
        setupFunctionButtons()
        updateDisplay()
    }

    private fun setupNumberButtons() {
        val digitButtons = mapOf(
            binding.btn0 to "0", binding.btn1 to "1", binding.btn2 to "2",
            binding.btn3 to "3", binding.btn4 to "4", binding.btn5 to "5",
            binding.btn6 to "6", binding.btn7 to "7", binding.btn8 to "8",
            binding.btn9 to "9"
        )
        digitButtons.forEach { (button, digit) -> button.setOnClickListener { onDigit(digit) } }
        binding.btnDot.setOnClickListener { onDot() }
    }

    private fun setupOperatorButtons() {
        binding.btnPlus.setOnClickListener { onOperator(Operator.ADD) }
        binding.btnMinus.setOnClickListener { onOperator(Operator.SUBTRACT) }
        binding.btnMultiply.setOnClickListener { onOperator(Operator.MULTIPLY) }
        binding.btnDivide.setOnClickListener { onOperator(Operator.DIVIDE) }
        binding.btnEquals.setOnClickListener { onEquals() }
    }

    private fun setupFunctionButtons() {
        binding.btnClear.setOnClickListener { onClear() }
        binding.btnPlusMinus.setOnClickListener { onToggleSign() }
        binding.btnPercent.setOnClickListener { onPercent() }
    }

    private fun onDigit(digit: String) {
        if (lastResultShown) {
            currentInput = digit
            expressionText = ""
            lastResultShown = false
        } else if (startFreshInput || currentInput == "0") {
            currentInput = digit
        } else {
            if (currentInput.length < 15) {
                currentInput += digit
            }
        }
        startFreshInput = false
        updateDisplay()
    }

    private fun onDot() {
        if (lastResultShown) {
            currentInput = "0."
            expressionText = ""
            lastResultShown = false
        } else if (startFreshInput) {
            currentInput = "0."
        } else if (!currentInput.contains(".")) {
            currentInput += "."
        }
        startFreshInput = false
        updateDisplay()
    }

    private fun onOperator(operator: Operator) {
        lastResultShown = false
        val inputValue = currentInput.toBigDecimalOrZero()

        if (pendingOperator != null && !startFreshInput) {
            val result = applyOperator(storedValue ?: BigDecimal.ZERO, inputValue, pendingOperator!!)
            if (result == null) {
                showError()
                return
            }
            storedValue = result
            currentInput = formatResult(result)
        } else {
            storedValue = inputValue
        }

        pendingOperator = operator
        expressionText = "${formatResult(storedValue!!)} ${operator.symbol}"
        startFreshInput = true
        updateDisplay()
    }

    private fun onEquals() {
        val operator = pendingOperator ?: return
        val inputValue = currentInput.toBigDecimalOrZero()
        val left = storedValue ?: BigDecimal.ZERO

        expressionText = "${formatResult(left)} ${operator.symbol} ${formatResult(inputValue)} ="

        val result = applyOperator(left, inputValue, operator)
        if (result == null) {
            showError()
            return
        }
        currentInput = formatResult(result)

        storedValue = null
        pendingOperator = null
        startFreshInput = true
        lastResultShown = true
        updateDisplay()
    }

    private fun showError() {
        currentInput = "Error"
        storedValue = null
        pendingOperator = null
        startFreshInput = true
        lastResultShown = true
        updateDisplay()
    }

    private fun onClear() {
        currentInput = "0"
        storedValue = null
        pendingOperator = null
        expressionText = ""
        startFreshInput = true
        lastResultShown = false
        updateDisplay()
    }

    private fun onToggleSign() {
        val value = currentInput.toBigDecimalOrZero()
        currentInput = formatResult(value.negate())
        updateDisplay()
    }

    private fun onPercent() {
        val value = currentInput.toBigDecimalOrZero()
        val result = value.divide(BigDecimal(100), MathContext.DECIMAL64)
        currentInput = formatResult(result)
        startFreshInput = true
        updateDisplay()
    }

    private fun applyOperator(left: BigDecimal, right: BigDecimal, operator: Operator): BigDecimal? {
        return when (operator) {
            Operator.ADD -> left.add(right)
            Operator.SUBTRACT -> left.subtract(right)
            Operator.MULTIPLY -> left.multiply(right)
            Operator.DIVIDE -> {
                if (right.compareTo(BigDecimal.ZERO) == 0) {
                    null
                } else {
                    left.divide(right, MathContext.DECIMAL64)
                }
            }
        }
    }

    private fun formatResult(value: BigDecimal): String {
        val stripped = value.stripTrailingZeros().setScale(
            value.stripTrailingZeros().scale().coerceAtLeast(0), RoundingMode.HALF_UP
        )
        return stripped.toPlainString()
    }

    private fun String.toBigDecimalOrZero(): BigDecimal {
        return this.toBigDecimalOrNull() ?: BigDecimal.ZERO
    }

    private fun updateDisplay() {
        binding.tvExpression.text = expressionText
        binding.tvResult.text = currentInput
    }
}
