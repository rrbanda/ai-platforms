"""Pipeline unit tests.

Fast, no-cluster tests that validate pipeline compilation, config integrity,
and quality gate logic. Run with:

    cd pipeline/
    pytest tests/ -v

Or in CI:
    python -m pytest tests/ -v --tb=short
"""

import os
import sys
import textwrap

import pytest
import yaml

# ---------------------------------------------------------------------------
# Path setup — allow imports from the pipeline package
# ---------------------------------------------------------------------------
_PIPELINE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, _PIPELINE_DIR)
sys.path.insert(0, os.path.join(_PIPELINE_DIR, "local_components"))

_CONFIG_PATH = os.path.join(_PIPELINE_DIR, "pipeline-config.yaml")


# ===========================================================================
# 1. Config validation
# ===========================================================================
class TestPipelineConfig:
    """Validate pipeline-config.yaml structure and required keys."""

    @pytest.fixture(autouse=True)
    def load_config(self):
        with open(_CONFIG_PATH) as f:
            self.config = yaml.safe_load(f)

    def test_config_loads(self):
        assert self.config is not None
        assert isinstance(self.config, dict)

    def test_required_top_level_sections(self):
        required = ["images", "pipeline", "infrastructure", "services", "defaults", "evaluation"]
        for key in required:
            assert key in self.config, f"Missing required config section: {key}"

    def test_pipeline_identity(self):
        pipeline = self.config["pipeline"]
        assert "name" in pipeline
        assert "version" in pipeline
        assert isinstance(pipeline["name"], str)
        assert len(pipeline["name"]) > 0

    def test_infrastructure_keys(self):
        infra = self.config["infrastructure"]
        assert "pvc_size" in infra
        assert "pvc_storage_class" in infra
        assert "namespace" in infra

    def test_services_keys(self):
        services = self.config["services"]
        assert "evalhub_url" in services
        assert "mlflow_experiment" in services
        assert "registry_address" in services
        assert len(services["mlflow_experiment"]) > 0, "mlflow_experiment must not be empty"

    def test_defaults_keys(self):
        defaults = self.config["defaults"]
        required = ["technique", "base_model", "dataset_uri", "epochs", "learning_rate"]
        for key in required:
            assert key in defaults, f"Missing default: {key}"

    def test_evaluation_keys(self):
        evaluation = self.config["evaluation"]
        assert "benchmarks" in evaluation
        assert "holdout_tasks" in evaluation
        assert "min_eval_score" in evaluation
        assert isinstance(evaluation["benchmarks"], list)
        assert len(evaluation["benchmarks"]) > 0

    def test_min_eval_score_is_numeric(self):
        score = self.config["evaluation"]["min_eval_score"]
        assert isinstance(score, (int, float)), f"min_eval_score must be numeric, got {type(score)}"
        assert score >= 0.0, "min_eval_score must be non-negative"

    def test_images_keys(self):
        images = self.config["images"]
        assert "pipeline_base" in images
        assert "eval_cuda" in images

    def test_defaults_has_run_name(self):
        defaults = self.config["defaults"]
        assert "run_name" in defaults, "Missing default: run_name"
        assert len(defaults["run_name"]) > 0

    def test_defaults_has_registry_stage(self):
        defaults = self.config["defaults"]
        assert "registry_stage" in defaults, "Missing default: registry_stage"
        assert defaults["registry_stage"] in ("dev", "staging", "prod"), (
            f"registry_stage must be dev/staging/prod, got '{defaults['registry_stage']}'"
        )

    def test_no_dead_model_download_phase(self):
        """Ensure pipeline docstring no longer references a standalone model download phase."""
        with open(os.path.join(_PIPELINE_DIR, "finetuning_pipeline.py")) as f:
            source = f.read()
        assert "download_base_model" not in source, (
            "Dead code: download_base_model function should have been removed"
        )


# ===========================================================================
# 2. Pipeline compilation
# ===========================================================================
class TestPipelineCompilation:
    """Verify the pipeline compiles without errors (no cluster needed)."""

    def test_syntax_valid(self):
        import ast

        pipeline_path = os.path.join(_PIPELINE_DIR, "finetuning_pipeline.py")
        with open(pipeline_path) as f:
            source = f.read()
        try:
            ast.parse(source)
        except SyntaxError as e:
            pytest.fail(f"Pipeline has syntax error: {e}")

    def test_pipeline_function_exists(self):
        from finetuning_pipeline import finetuning_pipeline

        assert callable(finetuning_pipeline)

    def test_quality_gate_function_exists(self):
        from finetuning_pipeline import eval_quality_gate

        assert callable(eval_quality_gate)

    @pytest.fixture(autouse=True)
    def _parse_pipeline_params(self):
        """Parse pipeline function parameters via AST (KFP decorators hide the signature)."""
        import ast

        pipeline_path = os.path.join(_PIPELINE_DIR, "finetuning_pipeline.py")
        with open(pipeline_path) as f:
            tree = ast.parse(f.read())
        for node in ast.walk(tree):
            if isinstance(node, ast.FunctionDef) and node.name == "finetuning_pipeline":
                self.param_names = [arg.arg for arg in node.args.args]
                break
        else:
            pytest.fail("Could not find finetuning_pipeline function in AST")

    def test_pipeline_has_min_eval_score_param(self):
        assert "min_eval_score" in self.param_names, "Pipeline missing min_eval_score parameter"

    def test_pipeline_has_mlflow_experiment_param(self):
        assert "mlflow_experiment" in self.param_names, "Pipeline missing mlflow_experiment parameter"

    def test_pipeline_has_run_name_param(self):
        assert "run_name" in self.param_names, "Pipeline missing run_name parameter"

    def test_pipeline_has_registry_stage_param(self):
        assert "registry_stage" in self.param_names, "Pipeline missing registry_stage parameter"


# ===========================================================================
# 3. Quality gate logic
# ===========================================================================
class TestQualityGateLogic:
    """Test the quality gate threshold logic in isolation.

    These tests exercise the core decision logic without running KFP
    or connecting to any cluster/MLflow.
    """

    @staticmethod
    def _run_gate(evalhub_score, holdout_scores, threshold):
        """Simulate the quality gate decision logic.

        Extracts the pure logic from the eval_quality_gate component
        so it can be tested without KFP runtime.
        """
        best_score = evalhub_score
        if best_score is None and holdout_scores:
            best_score = max(holdout_scores.values())
        if best_score is None:
            best_score = 0.0

        passed = not (threshold > 0.0 and best_score < threshold)
        return passed, best_score

    def test_gate_disabled_always_passes(self):
        passed, _ = self._run_gate(evalhub_score=0.1, holdout_scores={}, threshold=0.0)
        assert passed is True

    def test_gate_passes_above_threshold(self):
        passed, _ = self._run_gate(evalhub_score=0.85, holdout_scores={}, threshold=0.7)
        assert passed is True

    def test_gate_fails_below_threshold(self):
        passed, _ = self._run_gate(evalhub_score=0.3, holdout_scores={}, threshold=0.7)
        assert passed is False

    def test_gate_exact_threshold_passes(self):
        passed, _ = self._run_gate(evalhub_score=0.7, holdout_scores={}, threshold=0.7)
        assert passed is True

    def test_gate_falls_through_to_holdout(self):
        """When EvalHub is skipped (score=None), gate uses holdout scores."""
        passed, best = self._run_gate(
            evalhub_score=None,
            holdout_scores={"acc": 0.9, "f1": 0.85},
            threshold=0.7,
        )
        assert passed is True
        assert best == 0.9

    def test_gate_holdout_below_threshold(self):
        passed, _ = self._run_gate(
            evalhub_score=None,
            holdout_scores={"acc": 0.3},
            threshold=0.5,
        )
        assert passed is False

    def test_gate_no_scores_threshold_disabled(self):
        passed, best = self._run_gate(evalhub_score=None, holdout_scores={}, threshold=0.0)
        assert passed is True
        assert best == 0.0

    def test_gate_no_scores_threshold_enabled_fails(self):
        passed, best = self._run_gate(evalhub_score=None, holdout_scores={}, threshold=0.5)
        assert passed is False
        assert best == 0.0

    def test_gate_evalhub_takes_priority_over_holdout(self):
        """EvalHub score is used when available, even if holdout is higher."""
        passed, best = self._run_gate(
            evalhub_score=0.4,
            holdout_scores={"acc": 0.9},
            threshold=0.5,
        )
        assert passed is False
        assert best == 0.4


# ===========================================================================
# 4. Model registry component
# ===========================================================================
class TestModelRegistryComponent:
    """Verify the model_registry component has the registry_stage parameter."""

    def test_registry_has_stage_param(self):
        import ast

        registry_path = os.path.join(_PIPELINE_DIR, "local_components", "model_registry.py")
        with open(registry_path) as f:
            tree = ast.parse(f.read())
        for node in ast.walk(tree):
            if isinstance(node, ast.FunctionDef) and node.name == "kubeflow_model_registry":
                param_names = [arg.arg for arg in node.args.args]
                assert "registry_stage" in param_names, "model_registry missing registry_stage parameter"
                return
        pytest.fail("Could not find kubeflow_model_registry function")

    def test_registry_stage_stored_in_metadata(self):
        registry_path = os.path.join(_PIPELINE_DIR, "local_components", "model_registry.py")
        with open(registry_path) as f:
            source = f.read()
        assert 'version_metadata["stage"]' in source, (
            "model_registry must store registry_stage in version_metadata['stage']"
        )


# ===========================================================================
# 5. DAG structure
# ===========================================================================
class TestDAGStructure:
    """Verify the pipeline DAG has the expected task dependencies."""

    def test_compiled_yaml_has_quality_gate(self):
        compiled_path = os.path.join(_PIPELINE_DIR, "finetuning_pipeline.yaml")
        if not os.path.exists(compiled_path):
            pytest.skip("Compiled pipeline YAML not found (run build_pipeline.py first)")
        with open(compiled_path) as f:
            content = f.read()
        assert "eval-quality-gate" in content, "Compiled pipeline missing eval-quality-gate task"

    def test_compiled_yaml_has_registry_after_gate(self):
        compiled_path = os.path.join(_PIPELINE_DIR, "finetuning_pipeline.yaml")
        if not os.path.exists(compiled_path):
            pytest.skip("Compiled pipeline YAML not found (run build_pipeline.py first)")
        with open(compiled_path) as f:
            content = f.read()
        assert "eval-quality-gate" in content
        assert "kubeflow-model-registry" in content


# ===========================================================================
# 6. Fixture-based component tests
#    Exercises component logic with saved metrics from a real successful run.
#    No cluster, no GPU, no KFP runtime needed.
# ===========================================================================
_FIXTURES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")


def _load_fixture(name: str) -> dict:
    import json

    with open(os.path.join(_FIXTURES_DIR, name)) as f:
        data = json.load(f)
    data.pop("_comment", None)
    return data


class TestQualityGateWithFixtures:
    """Test the quality gate decision logic using real metrics fixtures."""

    @pytest.fixture(autouse=True)
    def load_fixtures(self):
        self.eval_meta = _load_fixture("eval_metrics.json")
        self.holdout_meta = _load_fixture("holdout_metrics.json")
        self.training_meta = _load_fixture("training_metrics.json")

    @staticmethod
    def _run_gate_with_fixtures(eval_meta, holdout_meta, threshold):
        """Replicate the gate logic using fixture dicts (same as component)."""
        _SKIP = {"display_name", "store_session_info"}
        evalhub_score = None
        state = eval_meta.get("evalhub_state", "unknown")
        if state != "skipped":
            raw = eval_meta.get("eval_overall_score")
            if raw is not None:
                evalhub_score = float(raw)

        holdout_scores = {}
        for k, v in holdout_meta.items():
            if k not in _SKIP and isinstance(v, (int, float)):
                holdout_scores[k] = float(v)

        best = evalhub_score
        if best is None and holdout_scores:
            best = max(holdout_scores.values())
        if best is None:
            best = 0.0

        passed = not (threshold > 0.0 and best < threshold)
        return passed, best, evalhub_score, holdout_scores

    def test_fixture_gate_passes_default_threshold(self):
        passed, best, _, _ = self._run_gate_with_fixtures(self.eval_meta, self.holdout_meta, 0.0)
        assert passed is True

    def test_fixture_gate_passes_realistic_threshold(self):
        passed, best, _, _ = self._run_gate_with_fixtures(self.eval_meta, self.holdout_meta, 0.5)
        assert passed is True
        assert best == 0.72

    def test_fixture_gate_fails_high_threshold(self):
        passed, best, _, _ = self._run_gate_with_fixtures(self.eval_meta, self.holdout_meta, 0.9)
        assert passed is False

    def test_fixture_holdout_scores_extracted(self):
        _, _, _, holdout = self._run_gate_with_fixtures(self.eval_meta, self.holdout_meta, 0.0)
        assert "acc" in holdout
        assert "acc_norm" in holdout
        assert holdout["acc"] == 0.68

    def test_fixture_training_params_present(self):
        assert self.training_meta["technique"] == "lora"
        assert self.training_meta["learning_rate"] == 0.0002
        assert self.training_meta["num_epochs"] == 2.0

    def test_fixture_evalhub_score_extracted(self):
        _, _, score, _ = self._run_gate_with_fixtures(self.eval_meta, self.holdout_meta, 0.0)
        assert score == 0.72

    def test_fixture_skipped_evalhub_falls_to_holdout(self):
        skipped = dict(self.eval_meta)
        skipped["evalhub_state"] = "skipped"
        passed, best, score, _ = self._run_gate_with_fixtures(skipped, self.holdout_meta, 0.5)
        assert score is None
        assert best == 0.71
        assert passed is True

    def test_fixture_mlflow_params_vs_metrics_split(self):
        """Training params that are strings go to mlflow.log_param, numerics to log_metric."""
        params = {}
        metrics = {}
        for k, v in self.training_meta.items():
            if isinstance(v, (int, float)):
                metrics[f"training/{k}"] = float(v)
            else:
                params[f"training/{k}"] = str(v)
        assert "training/technique" in params
        assert "training/learning_rate" in metrics
        assert "training/num_epochs" in metrics
        assert len(params) + len(metrics) == len(self.training_meta)
