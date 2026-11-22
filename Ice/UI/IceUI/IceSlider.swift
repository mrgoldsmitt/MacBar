//
//  IceSlider.swift
//  MacBar
//

import SwiftUI

struct IceSlider<Value: BinaryFloatingPoint, ValueLabel: View>: View {
    @Binding private var value: Value

    private let bounds: ClosedRange<Value>
    private let step: Value?
    private let valueLabel: ValueLabel

    init(
        value: Binding<Value>,
        in bounds: ClosedRange<Value>,
        step: Value? = nil,
        @ViewBuilder valueLabel: () -> ValueLabel
    ) {
        self._value = value
        self.bounds = bounds
        self.step = step
        self.valueLabel = valueLabel()
    }

    init(
        _ valueLabelKey: LocalizedStringKey,
        value: Binding<Value>,
        in bounds: ClosedRange<Value>,
        step: Value? = nil
    ) where ValueLabel == Text {
        self._value = value
        self.bounds = bounds
        self.step = step
        self.valueLabel = Text(valueLabelKey)
    }

    private var doubleBinding: Binding<Double> {
        Binding(
            get: { Double(value) },
            set: { value = Value($0) }
        )
    }

    private var doubleBounds: ClosedRange<Double> {
        Double(bounds.lowerBound)...Double(bounds.upperBound)
    }

    var body: some View {
        HStack(spacing: 10) {
            if let step, Double(step) > 0 {
                Slider(value: doubleBinding, in: doubleBounds, step: Double(step))
            } else {
                Slider(value: doubleBinding, in: doubleBounds)
            }

            valueLabel
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 70, alignment: .trailing)
        }
    }
}
