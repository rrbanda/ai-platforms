"""Tests for technique modules — build_params, defaults, and safety guards."""

import pytest


class TestLoRA:
    """Tests for the LoRA technique module."""

    def _mod(self):
        from shared.techniques import lora
        return lora

    def test_defaults(self):
        mod = self._mod()
        assert mod.ALGORITHM_NAME == "LORA_SFT"
        assert mod.IS_SINGLE_NODE is True
        assert mod.DEFAULT_LR == 2e-4
        assert mod.DEFAULT_EPOCHS == 3
        assert mod.DEFAULT_MEMORY == "32Gi"
        assert mod.DEFAULT_MAX_TOKENS == 32000
        assert mod.DEFAULT_CPU == "4"

    def test_build_params_sets_backend(self):
        common = {}
        self._mod().build_params(common, lora_r=8, lora_alpha=16)
        assert common["backend"] == "unsloth"
        assert common["lora_r"] == 8
        assert common["lora_alpha"] == 16

    def test_flash_attention_enables_sample_packing(self):
        common = {}
        self._mod().build_params(
            common, lora_flash_attention=True, lora_sample_packing=False
        )
        assert common["flash_attention"] is True
        assert common["sample_packing"] is True

    def test_sample_packing_stays_false_without_flash_attention(self):
        common = {}
        self._mod().build_params(
            common, lora_flash_attention=False, lora_sample_packing=False
        )
        assert common["flash_attention"] is False
        assert common["sample_packing"] is False

    def test_qloRA_mutual_exclusion(self):
        with pytest.raises(ValueError, match="Cannot enable both"):
            self._mod().build_params(
                {}, lora_load_in_4bit=True, lora_load_in_8bit=True
            )

    def test_4bit_quantization(self):
        common = {}
        self._mod().build_params(common, lora_load_in_4bit=True, lora_load_in_8bit=False)
        assert common["load_in_4bit"] is True
        assert common.get("load_in_8bit") is False

    def test_target_modules_parsed(self):
        common = {}
        self._mod().build_params(common, lora_target_modules="q_proj, k_proj, v_proj")
        assert common["target_modules"] == ["q_proj", "k_proj", "v_proj"]

    def test_optional_int_params(self):
        common = {}
        self._mod().build_params(
            common, lora_micro_batch_size=4, lora_gradient_accumulation_steps=2,
            lora_save_steps=100, lora_logging_steps=10, lora_save_total_limit=3,
        )
        assert common["micro_batch_size"] == 4
        assert common["gradient_accumulation_steps"] == 2
        assert common["save_steps"] == 100

    def test_none_values_skipped(self):
        common = {}
        self._mod().build_params(common, lora_use_rslora=None, lora_use_dora=None)
        assert "use_rslora" not in common
        assert "use_dora" not in common


class TestSFT:
    """Tests for the SFT technique module."""

    def _mod(self):
        from shared.techniques import sft
        return sft

    def test_defaults(self):
        mod = self._mod()
        assert mod.ALGORITHM_NAME == "SFT"
        assert mod.IS_SINGLE_NODE is False
        assert mod.DEFAULT_LR == 5e-6
        assert mod.DEFAULT_EPOCHS == 1
        assert mod.DEFAULT_MEMORY == "64Gi"
        assert mod.DEFAULT_MAX_TOKENS == 10000
        assert mod.DEFAULT_CPU == "4"
        assert len(mod.METRICS_FILES) > 0

    def test_build_params_fsdp(self):
        common = {}
        self._mod().build_params(common, sft_fsdp_sharding_strategy="full_shard")
        assert common["fsdp_sharding_strategy"] == "FULL_SHARD"

    def test_build_params_save_samples(self):
        common = {}
        self._mod().build_params(common, sft_save_samples=100)
        assert common["save_samples"] == 100

    def test_build_params_full_state_at_epoch(self):
        common = {}
        self._mod().build_params(common, sft_accelerate_full_state_at_epoch=True)
        assert common["accelerate_full_state_at_epoch"] is True


class TestOSFT:
    """Tests for the OSFT technique module."""

    def _mod(self):
        from shared.techniques import osft
        return osft

    def test_defaults(self):
        mod = self._mod()
        assert mod.ALGORITHM_NAME == "OSFT"
        assert mod.IS_SINGLE_NODE is False
        assert mod.DEFAULT_LR == 5e-6
        assert mod.DEFAULT_MEMORY == "64Gi"
        assert mod.DEFAULT_MAX_TOKENS == 64000
        assert mod.DEFAULT_CPU == "8"
        assert mod.DEFAULT_MEMORY_EFFICIENT_INIT is True

    def test_build_params_unfreeze_ratio(self):
        common = {}
        import sys
        from unittest import mock
        sys.modules.setdefault("setup", mock.MagicMock(parse_kv=lambda s: dict(kv.split("=") for kv in s.split(",") if "=" in kv)))
        self._mod().build_params(common, osft_unfreeze_rank_ratio=0.3)
        assert common["unfreeze_rank_ratio"] == 0.3

    def test_build_params_target_patterns(self):
        common = {}
        import sys
        from unittest import mock
        sys.modules.setdefault("setup", mock.MagicMock(parse_kv=lambda s: dict(kv.split("=") for kv in s.split(",") if "=" in kv)))
        self._mod().build_params(common, osft_target_patterns="layer.0, layer.1")
        assert common["target_patterns"] == ["layer.0", "layer.1"]

    def test_build_params_fsdp(self):
        common = {}
        import sys
        from unittest import mock
        sys.modules.setdefault("setup", mock.MagicMock(parse_kv=lambda s: dict(kv.split("=") for kv in s.split(",") if "=" in kv)))
        self._mod().build_params(common, osft_fsdp_sharding_strategy="hybrid_shard")
        assert common["fsdp_sharding_strategy"] == "HYBRID_SHARD"

    def test_build_params_bool_flags(self):
        common = {}
        import sys
        from unittest import mock
        sys.modules.setdefault("setup", mock.MagicMock(parse_kv=lambda s: dict(kv.split("=") for kv in s.split(",") if "=" in kv)))
        self._mod().build_params(
            common,
            osft_memory_efficient_init=True,
            osft_unmask_messages=True,
            osft_use_processed_dataset=False,
            osft_save_final_checkpoint=True,
        )
        assert common["memory_efficient_init"] is True
        assert common["unmask_messages"] is True
        assert common["use_processed_dataset"] is False
        assert common["save_final_checkpoint"] is True


class TestCustom:
    """Tests for the custom technique module."""

    def _mod(self):
        from shared.techniques import custom
        return custom

    def test_defaults(self):
        mod = self._mod()
        assert mod.IS_SINGLE_NODE is True
        assert mod.DEFAULT_LR == 2e-4

    def test_build_params_is_noop(self):
        common = {"model_path": "/test"}
        result = self._mod().build_params(common)
        assert result == common


class TestTechniqueDispatch:
    """Tests for the technique dispatch in __init__.py."""

    def test_supported_techniques(self):
        from shared.techniques import SUPPORTED_TECHNIQUES
        assert "lora" in SUPPORTED_TECHNIQUES
        assert "sft" in SUPPORTED_TECHNIQUES
        assert "osft" in SUPPORTED_TECHNIQUES
        assert "custom" in SUPPORTED_TECHNIQUES

    def test_get_lora_direct(self):
        from shared.techniques import lora
        assert lora.ALGORITHM_NAME == "LORA_SFT"

    def test_get_sft_direct(self):
        from shared.techniques import sft
        assert sft.ALGORITHM_NAME == "SFT"

    def test_get_osft_direct(self):
        from shared.techniques import osft
        assert osft.ALGORITHM_NAME == "OSFT"

    def test_unknown_technique_raises(self):
        from shared.techniques import get_technique_module
        with pytest.raises(ValueError, match="Unknown technique"):
            get_technique_module("unknown")
